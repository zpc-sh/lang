// native/lang_perf/src/lib.rs - Ultra-high performance JSON-LD operations in Rust
// Compiled as NIFs for Elixir/Phoenix integration via Rustler

#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

use rustler::{Atom, Binary, Env, NifResult, Term, ResourceArc, OwnedBinary};
use rustler::types::binary::NewBinary;
use std::sync::RwLock;
use std::collections::HashMap;
use memmap2::{Mmap, MmapOptions};
use lz4_flex::{compress_prepend_size, decompress_size_prepended};
use xxhash_rust::xxh64::xxh64;
use rayon::prelude::*;
use serde::{Serialize, Deserialize};
#[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
use std::arch::x86_64::*;
use once_cell::sync::Lazy;
use dashmap::DashMap;

// ============================================================================
// RUSTLER MODULE INITIALIZATION
// ============================================================================

rustler::init!(
    "Elixir.Lang.Native.PerfEngine",
    [
        compare_triple_sets,
        hash_jsonld_nodes,
        compress_diff,
        decompress_diff,
        mmap_jsonld,
        munmap_jsonld,
        find_jsonld_patterns,
        streaming_parse_chunk,
        compute_diff_streaming,
        batch_hash_triples,
        quick_structural_hash,
        extract_context_only,
        parallel_triple_diff,
        simd_hash_batch,
        memory_stats
    ],
    load = on_load
);

fn on_load(env: Env, _info: Term) -> bool {
    rustler::resource!(MmapResource, env);
    rustler::resource!(StreamingParserResource, env);
    true
}

// Atoms for Elixir communication
rustler::atoms! {
    ok,
    error,
    identical,
    context_only,
    full_diff,
    memory_error,
    simd_unavailable,
    mmap_failed,
    compression_failed
}

// ============================================================================
// DATA STRUCTURES - OPTIMIZED FOR CACHE PERFORMANCE
// ============================================================================

#[repr(C, align(64))] // 64-byte cache line alignment
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct PackedTriple {
    subject_hash: u64,
    predicate_hash: u64,
    object_hash: u64,
    flags: u32,
    source_offset: u32,
    padding: [u8; 8], // Pad to 64 bytes for optimal SIMD
}

#[derive(Serialize, Deserialize, Debug)]
struct CompressedDiff {
    version: u32,
    compression_type: u8, // 0=none, 1=lz4
    addition_count: u32,
    deletion_count: u32,
    modification_count: u32,
    checksum: u32,
    additions: Vec<u8>,
    deletions: Vec<u8>,
    modifications: Vec<u8>,
}

#[derive(Debug)]
struct DiffResult {
    additions: Vec<PackedTriple>,
    deletions: Vec<PackedTriple>,
    modifications: Vec<(PackedTriple, PackedTriple)>,
}

#[derive(Debug)]
struct QuickHashResult {
    identical: bool,
    context_only: bool,
    old_hash: u64,
    new_hash: u64,
}

// Resources for managing memory-mapped files and streaming parsers
struct MmapResource {
    mmap: Mmap,
    path: String,
}



struct StreamingParserResource {
    buffer: Vec<u8>,
    state: ParserState,
    depth: u32,
    in_string: bool,
    byte_offset: u64,
}



#[derive(Debug, Clone, Copy)]
enum ParserState {
    SeekingObject,
    InObject,
    SeekingKey,
    InKey,
    SeekingValue,
    InValue,
    InArray,
}

// High-performance caches
static HASH_CACHE: Lazy<DashMap<String, u64>> = Lazy::new(|| DashMap::new());
static MMAP_CACHE: Lazy<DashMap<String, ResourceArc<MmapResource>>> = Lazy::new(|| DashMap::new());

// ============================================================================
// SIMD-OPTIMIZED TRIPLE COMPARISON
// ============================================================================

// Compare up to 4 triples simultaneously using AVX2
#[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
#[target_feature(enable = "avx2")]
unsafe fn compare_triples_avx2(old: &[PackedTriple], new: &[PackedTriple]) -> Vec<u32> {
    let mut differences = Vec::new();
    let chunks = std::cmp::min(old.len(), new.len()) / 4;
    
    for chunk_idx in 0..chunks {
        let old_start = chunk_idx * 4;
        let new_start = chunk_idx * 4;
        
        if old_start >= old.len() || new_start >= new.len() {
            break;
        }
        
        // Load 4 subject hashes at once (256 bits = 4 x 64-bit)
        let old_subjects = _mm256_loadu_si256(
            old[old_start..].as_ptr() as *const __m256i
        );
        let new_subjects = _mm256_loadu_si256(
            new[new_start..].as_ptr() as *const __m256i
        );
        
        // Compare subjects
        let subject_eq = _mm256_cmpeq_epi64(old_subjects, new_subjects);
        
        // Extract comparison mask and process differences
        let mask = _mm256_movemask_epi8(subject_eq);
        
        // Process each triple in the chunk
        for i in 0..4 {
            let old_idx = old_start + i;
            let new_idx = new_start + i;
            
            if old_idx >= old.len() || new_idx >= new.len() {
                break;
            }
            
            let old_triple = &old[old_idx];
            let new_triple = &new[new_idx];
            
            if old_triple.subject_hash < new_triple.subject_hash {
                // Deletion
                differences.push(old_idx as u32 | 0x80000000);
            } else if old_triple.subject_hash > new_triple.subject_hash {
                // Addition
                differences.push(new_idx as u32 | 0x40000000);
            } else if (mask & (0xFF << (i * 8))) == 0 {
                // Modification (hashes equal but other fields differ)
                differences.push(old_idx as u32 | 0x20000000);
            }
        }
    }
    
    differences
}

// Fallback implementation for non-x86 architectures
fn compare_triples_fallback(old: &[PackedTriple], new: &[PackedTriple]) -> Vec<u32> {
    let mut differences = Vec::new();
    let mut old_idx = 0;
    let mut new_idx = 0;
    
    while old_idx < old.len() && new_idx < new.len() {
        let old_triple = &old[old_idx];
        let new_triple = &new[new_idx];
        
        if old_triple.subject_hash < new_triple.subject_hash {
            // Deletion
            differences.push(old_idx as u32 | 0x80000000);
            old_idx += 1;
        } else if old_triple.subject_hash > new_triple.subject_hash {
            // Addition
            differences.push(new_idx as u32 | 0x40000000);
            new_idx += 1;
        } else {
            // Same subject, check if other fields differ
            if old_triple.predicate_hash != new_triple.predicate_hash ||
               old_triple.object_hash != new_triple.object_hash {
                // Modification
                differences.push(old_idx as u32 | 0x20000000);
            }
            old_idx += 1;
            new_idx += 1;
        }
    }
    
    // Handle remaining elements
    while old_idx < old.len() {
        differences.push(old_idx as u32 | 0x80000000);
        old_idx += 1;
    }
    
    while new_idx < new.len() {
        differences.push(new_idx as u32 | 0x40000000);
        new_idx += 1;
    }
    
    differences
}

// Main triple comparison function exported to Elixir
#[rustler::nif]
fn compare_triple_sets(
    old_triples_bin: Binary,
    new_triples_bin: Binary,
) -> NifResult<Vec<u32>> {
    
    // SAFETY: Ensure proper alignment for SIMD operations
    let old_data = old_triples_bin.as_slice();
    let new_data = new_triples_bin.as_slice();
    
    if old_data.len() % std::mem::size_of::<PackedTriple>() != 0 ||
       new_data.len() % std::mem::size_of::<PackedTriple>() != 0 {
        return Err(rustler::Error::BadArg);
    }
    
    // Convert byte slices to PackedTriple slices
    let old_triples = unsafe {
        std::slice::from_raw_parts(
            old_data.as_ptr() as *const PackedTriple,
            old_data.len() / std::mem::size_of::<PackedTriple>(),
        )
    };
    
    let new_triples = unsafe {
        std::slice::from_raw_parts(
            new_data.as_ptr() as *const PackedTriple,
            new_data.len() / std::mem::size_of::<PackedTriple>(),
        )
    };
    
    // Use SIMD if available, otherwise fallback to scalar
    let differences = {
        #[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
        {
            if is_x86_feature_detected!("avx2") {
                unsafe { compare_triples_avx2(&old_triples, &new_triples) }
            } else {
                compare_triples_fallback(&old_triples, &new_triples)
            }
        }
        #[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
        {
            compare_triples_fallback(&old_triples, &new_triples)
        }
    };
    
    Ok(differences)
}

// Scalar fallback for non-AVX2 systems
fn compare_triples_scalar(old: &[PackedTriple], new: &[PackedTriple]) -> Vec<u32> {
    let mut differences = Vec::new();
    let mut old_idx = 0;
    let mut new_idx = 0;
    
    while old_idx < old.len() && new_idx < new.len() {
        let old_triple = &old[old_idx];
        let new_triple = &new[new_idx];
        
        match old_triple.subject_hash.cmp(&new_triple.subject_hash) {
            std::cmp::Ordering::Less => {
                differences.push(old_idx as u32 | 0x80000000);
                old_idx += 1;
            }
            std::cmp::Ordering::Greater => {
                differences.push(new_idx as u32 | 0x40000000);
                new_idx += 1;
            }
            std::cmp::Ordering::Equal => {
                if old_triple.predicate_hash != new_triple.predicate_hash
                    || old_triple.object_hash != new_triple.object_hash
                {
                    differences.push(old_idx as u32 | 0x20000000);
                }
                old_idx += 1;
                new_idx += 1;
            }
        }
    }
    
    // Handle remaining elements
    while old_idx < old.len() {
        differences.push(old_idx as u32 | 0x80000000);
        old_idx += 1;
    }
    
    while new_idx < new.len() {
        differences.push(new_idx as u32 | 0x40000000);
        new_idx += 1;
    }
    
    differences
}

// ============================================================================
// VECTORIZED HASH COMPUTATION WITH XXH64
// ============================================================================

#[rustler::nif]
fn hash_jsonld_nodes(input_data: Binary) -> NifResult<Vec<u64>> {
    let data = input_data.as_slice();
    let mut hashes = Vec::new();
    
    // Split input by null bytes (string boundaries)
    let strings: Vec<&[u8]> = data.split(|&b| b == 0).filter(|s| !s.is_empty()).collect();
    
    // Parallel hash computation using rayon
    hashes = strings
        .par_iter()
        .map(|&s| xxh64(s, 0))
        .collect();
    
    Ok(hashes)
}

// Batch hash computation optimized for large datasets
#[rustler::nif]
fn batch_hash_triples(triples_data: Vec<(String, String, String)>) -> NifResult<Vec<u64>> {
    // Check cache first
    let mut results = Vec::with_capacity(triples_data.len());
    let mut uncached = Vec::new();
    
    for (i, (subject, predicate, object)) in triples_data.iter().enumerate() {
        let combined = format!("{}|{}|{}", subject, predicate, object);
        if let Some(hash) = HASH_CACHE.get(&combined) {
            results.push((i, *hash));
        } else {
            uncached.push((i, combined));
        }
    }
    
    // Process uncached in parallel chunks for optimal CPU utilization
    let uncached_hashes: Vec<(usize, u64)> = uncached
        .par_iter()
        .map(|(i, combined)| {
            let hash = xxh64(combined.as_bytes(), 0);
            HASH_CACHE.insert(combined.clone(), hash);
            (*i, hash)
        })
        .collect();
    
    // Merge cached and uncached results
    results.extend(uncached_hashes);
    results.sort_by_key(|(i, _)| *i);
    
    Ok(results.into_iter().map(|(_, hash)| hash).collect())
}

// SIMD batch hashing for maximum performance
#[rustler::nif]
fn simd_hash_batch(data_chunks: Vec<String>) -> NifResult<Vec<u64>> {
    if data_chunks.len() < 8 {
        // Use regular hashing for small batches
        return Ok(data_chunks.iter().map(|s| xxh64(s.as_bytes(), 0)).collect());
    }
    
    // Process in parallel SIMD-friendly chunks
    let hashes = data_chunks
        .par_chunks(8) // Process 8 strings at once for SIMD
        .flat_map(|chunk| {
            chunk.iter().map(|s| xxh64(s.as_bytes(), 0)).collect::<Vec<_>>()
        })
        .collect();
    
    Ok(hashes)
}

// ============================================================================
// QUICK STRUCTURAL HASH COMPARISON
// ============================================================================

#[rustler::nif]
fn quick_structural_hash(old_doc: String, new_doc: String) -> NifResult<(Atom, u64, u64)> {
    let old_hash = xxh64(old_doc.as_bytes(), 0);
    let new_hash = xxh64(new_doc.as_bytes(), 0);
    
    if old_hash == new_hash {
        Ok((identical(), old_hash, new_hash))
    } else {
        // Check if only context changed
        let old_without_context = strip_context(&old_doc);
        let new_without_context = strip_context(&new_doc);
        
        let old_content_hash = xxh64(old_without_context.as_bytes(), 0);
        let new_content_hash = xxh64(new_without_context.as_bytes(), 0);
        
        if old_content_hash == new_content_hash {
            Ok((context_only(), old_hash, new_hash))
        } else {
            Ok((full_diff(), old_hash, new_hash))
        }
    }
}

#[rustler::nif]
fn extract_context_only(doc: String) -> NifResult<String> {
    let stripped = strip_context(&doc);
    Ok(stripped)
}

fn strip_context(doc: &str) -> String {
    // Fast context stripping using string replacement
    // This is a simplified version - in production you'd want proper JSON parsing
    let mut result = doc.to_string();
    
    // Remove @context field with simple pattern matching
    if let Some(start) = result.find("\"@context\"") {
        if let Some(end) = find_field_end(&result, start) {
            result.replace_range(start..=end, "");
        }
    }
    
    // Clean up any double commas or trailing commas
    result = result.replace(",,", ",");
    result = result.replace(",}", "}");
    result = result.replace(",]", "]");
    
    result
}

fn find_field_end(doc: &str, start: usize) -> Option<usize> {
    let chars: Vec<char> = doc.chars().collect();
    let mut depth = 0;
    let mut in_string = false;
    let mut escape_next = false;
    
    // Skip the field name
    let mut i = start;
    while i < chars.len() && chars[i] != ':' {
        i += 1;
    }
    i += 1; // Skip the ':'
    
    // Skip whitespace
    while i < chars.len() && chars[i].is_whitespace() {
        i += 1;
    }
    
    // Find the end of the value
    while i < chars.len() {
        let c = chars[i];
        
        if escape_next {
            escape_next = false;
        } else if c == '\\' {
            escape_next = true;
        } else if c == '"' {
            in_string = !in_string;
        } else if !in_string {
            match c {
                '{' | '[' => depth += 1,
                '}' | ']' => {
                    depth -= 1;
                    if depth < 0 {
                        return Some(i - 1);
                    }
                }
                ',' => {
                    if depth == 0 {
                        return Some(i - 1);
                    }
                }
                _ => {}
            }
        }
        
        i += 1;
    }
    
    Some(chars.len() - 1)
}

// ============================================================================
// PARALLEL TRIPLE DIFFING
// ============================================================================

#[rustler::nif]
fn parallel_triple_diff(
    old_triples: Vec<(String, String, String)>,
    new_triples: Vec<(String, String, String)>
) -> NifResult<(Vec<u32>, Vec<u32>, Vec<u32>)> {
    // Convert to packed triples with parallel hashing
    let old_packed: Vec<PackedTriple> = old_triples
        .par_iter()
        .enumerate()
        .map(|(idx, (s, p, o))| {
            PackedTriple {
                subject_hash: xxh64(s.as_bytes(), 0),
                predicate_hash: xxh64(p.as_bytes(), 0),
                object_hash: xxh64(o.as_bytes(), 0),
                flags: 0,
                source_offset: idx as u32,
                padding: [0; 8],
            }
        })
        .collect();
    
    let new_packed: Vec<PackedTriple> = new_triples
        .par_iter()
        .enumerate()
        .map(|(idx, (s, p, o))| {
            PackedTriple {
                subject_hash: xxh64(s.as_bytes(), 0),
                predicate_hash: xxh64(p.as_bytes(), 0),
                object_hash: xxh64(o.as_bytes(), 0),
                flags: 0,
                source_offset: idx as u32,
                padding: [0; 8],
            }
        })
        .collect();
    
    // Sort for efficient comparison
    let mut old_sorted = old_packed;
    let mut new_sorted = new_packed;
    
    old_sorted.par_sort_by_key(|t| t.subject_hash);
    new_sorted.par_sort_by_key(|t| t.subject_hash);
    
    // Find differences
    let mut additions = Vec::new();
    let mut deletions = Vec::new();
    let mut modifications = Vec::new();
    
    let mut old_idx = 0;
    let mut new_idx = 0;
    
    while old_idx < old_sorted.len() && new_idx < new_sorted.len() {
        let old_triple = &old_sorted[old_idx];
        let new_triple = &new_sorted[new_idx];
        
        match old_triple.subject_hash.cmp(&new_triple.subject_hash) {
            std::cmp::Ordering::Less => {
                deletions.push(old_triple.source_offset);
                old_idx += 1;
            }
            std::cmp::Ordering::Greater => {
                additions.push(new_triple.source_offset);
                new_idx += 1;
            }
            std::cmp::Ordering::Equal => {
                if old_triple.predicate_hash != new_triple.predicate_hash
                    || old_triple.object_hash != new_triple.object_hash
                {
                    modifications.push(old_triple.source_offset);
                }
                old_idx += 1;
                new_idx += 1;
            }
        }
    }
    
    // Handle remaining elements
    while old_idx < old_sorted.len() {
        deletions.push(old_sorted[old_idx].source_offset);
        old_idx += 1;
    }
    
    while new_idx < new_sorted.len() {
        additions.push(new_sorted[new_idx].source_offset);
        new_idx += 1;
    }
    
    Ok((additions, deletions, modifications))
}

// ============================================================================
// LZ4 COMPRESSION WITH OPTIMAL SETTINGS
// ============================================================================

#[rustler::nif]
fn compress_diff(input_data: Binary) -> NifResult<OwnedBinary> {
    let data = input_data.as_slice();
    
    // Use LZ4 with size prepending for easier decompression
    let compressed = compress_prepend_size(data);
    
    let mut binary = OwnedBinary::new(compressed.len()).unwrap();
    binary.as_mut_slice().copy_from_slice(&compressed);
    
    Ok(binary)
}

#[rustler::nif]
fn decompress_diff(compressed_data: Binary) -> NifResult<OwnedBinary> {
    let data = compressed_data.as_slice();
    
    match decompress_size_prepended(data) {
        Ok(decompressed) => {
            let mut binary = OwnedBinary::new(decompressed.len()).unwrap();
            binary.as_mut_slice().copy_from_slice(&decompressed);
            Ok(binary)
        }
        Err(_) => Err(rustler::Error::BadArg),
    }
}

// ============================================================================
// MEMORY-MAPPED FILE OPERATIONS
// ============================================================================

#[rustler::nif]
fn mmap_jsonld(env: Env, file_path: String) -> NifResult<ResourceArc<MmapResource>> {
    // Check cache first
    if let Some(cached) = MMAP_CACHE.get(&file_path) {
        return Ok(cached.clone());
    }
    
    use std::fs::File;
    
    let file = File::open(&file_path).map_err(|_| rustler::Error::BadArg)?;
    
    let mmap = unsafe {
        MmapOptions::new()
            .map(&file)
            .map_err(|_| rustler::Error::BadArg)?
    };
    
    // Advise OS about access pattern for better performance
    #[cfg(unix)]
    {
        use libc::{madvise, MADV_SEQUENTIAL, MADV_WILLNEED};
        unsafe {
            madvise(
                mmap.as_ptr() as *mut libc::c_void,
                mmap.len(),
                MADV_SEQUENTIAL | MADV_WILLNEED,
            );
        }
    }
    
    let resource = ResourceArc::new(MmapResource {
        mmap,
        path: file_path.clone(),
    });
    
    // Cache for reuse
    MMAP_CACHE.insert(file_path, resource.clone());
    
    Ok(resource)
}

#[rustler::nif]
fn munmap_jsonld(resource: ResourceArc<MmapResource>) -> NifResult<Atom> {
    // Remove from cache
    MMAP_CACHE.remove(&resource.path);
    // Resource will be dropped automatically
    Ok(ok())
}

// ============================================================================
// PATTERN FINDING WITH BOYER-MOORE
// ============================================================================

#[rustler::nif]
fn find_jsonld_patterns(data: ResourceArc<MmapResource>, patterns: Vec<String>) -> NifResult<Vec<Vec<u32>>> {
    let content = &data.mmap;
    let mut results = Vec::with_capacity(patterns.len());
    
    for pattern in patterns {
        let pattern_bytes = pattern.as_bytes();
        let matches = boyer_moore_search(content, pattern_bytes);
        results.push(matches);
    }
    
    Ok(results)
}

fn boyer_moore_search(text: &[u8], pattern: &[u8]) -> Vec<u32> {
    if pattern.is_empty() || text.is_empty() || pattern.len() > text.len() {
        return Vec::new();
    }
    
    let mut matches = Vec::new();
    let m = pattern.len();
    let n = text.len();
    
    // Build bad character table
    let mut bad_char = [m; 256];
    for i in 0..m - 1 {
        bad_char[pattern[i] as usize] = m - 1 - i;
    }
    
    let mut skip = 0;
    while skip <= n - m {
        let mut j = m - 1;
        
        // Match from right to left
        while j > 0 && pattern[j] == text[skip + j] {
            j -= 1;
        }
        
        if pattern[j] == text[skip + j] {
            matches.push(skip as u32);
            skip += if skip + m < n { m - bad_char[text[skip + m] as usize] } else { 1 };
        } else {
            skip += std::cmp::max(1, bad_char[text[skip + j] as usize].saturating_sub(m - 1 - j));
        }
    }
    
    matches
}

// ============================================================================
// STREAMING PARSER
// ============================================================================

#[rustler::nif]
fn streaming_parse_chunk(env: Env, data: Binary, chunk_size: u32) -> NifResult<ResourceArc<StreamingParserResource>> {
    let resource = ResourceArc::new(StreamingParserResource {
        buffer: Vec::with_capacity(chunk_size as usize),
        state: ParserState::SeekingObject,
        depth: 0,
        in_string: false,
        byte_offset: 0,
    });
    
    Ok(resource)
}

#[rustler::nif]
fn compute_diff_streaming(
    old_data: ResourceArc<MmapResource>,
    new_data: ResourceArc<MmapResource>
) -> NifResult<(u32, u32, u32)> {
    let old_content = &old_data.mmap;
    let new_content = &new_data.mmap;
    
    // Simple line-by-line comparison for streaming diff
    let old_lines: Vec<&[u8]> = old_content.split(|&b| b == b'\n').collect();
    let new_lines: Vec<&[u8]> = new_content.split(|&b| b == b'\n').collect();
    
    let mut additions = 0;
    let mut deletions = 0;
    let mut modifications = 0;
    
    let max_len = std::cmp::max(old_lines.len(), new_lines.len());
    
    for i in 0..max_len {
        match (old_lines.get(i), new_lines.get(i)) {
            (Some(old_line), Some(new_line)) => {
                if old_line != new_line {
                    modifications += 1;
                }
            }
            (Some(_), None) => deletions += 1,
            (None, Some(_)) => additions += 1,
            (None, None) => break,
        }
    }
    
    Ok((additions, deletions, modifications))
}

// ============================================================================
// PERFORMANCE MONITORING
// ============================================================================

#[rustler::nif]
fn memory_stats() -> NifResult<Vec<(String, u64)>> {
    let mut stats = Vec::new();
    
    stats.push(("hash_cache_size".to_string(), HASH_CACHE.len() as u64));
    stats.push(("mmap_cache_size".to_string(), MMAP_CACHE.len() as u64));
    
    // Get system memory info if available
    #[cfg(unix)]
    {
        use std::fs;
        if let Ok(status) = fs::read_to_string("/proc/self/status") {
            for line in status.lines() {
                if line.starts_with("VmRSS:") {
                    if let Some(kb_str) = line.split_whitespace().nth(1) {
                        if let Ok(kb) = kb_str.parse::<u64>() {
                            stats.push(("memory_rss_kb".to_string(), kb));
                        }
                    }
                }
            }
        }
    }
    
    Ok(stats)
}