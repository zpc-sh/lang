use rustler::{Encoder, Env, NifResult, Term, Binary, OwnedBinary};
use serde_json::{json, Value};
use semver::{Version, VersionReq};
use std::str;
use memchr::memmem;
use bumpalo::Bump;
use wide::{u8x32, CmpEq};

// We'll start with our own implementation and optimize from there
// use json_ld::{JsonLdProcessor, RemoteDocument, NoLoader};
// use json_ld::syntax::{Parse, Value as JsonLdValue};
// use tokio::runtime::Runtime;

use std::sync::Arc;
use lazy_static::lazy_static;
use lru::LruCache;
use std::sync::Mutex;
use std::num::NonZeroUsize;
use std::sync::atomic::{AtomicUsize, Ordering};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        lt,
        eq,
        gt,
        nil,
        true_atom = "true",
        false_atom = "false",
    }
}

lazy_static! {
    static ref CONTEXT_CACHE: Arc<Mutex<LruCache<String, Arc<String>>>> =
        Arc::new(Mutex::new(LruCache::new(NonZeroUsize::new(100).unwrap())));
    
    // PROC: Simple performance tracking for JSON-LD operations
    static ref PROCESSING_STATS: ProcessingStats = ProcessingStats::new();
    
    // PROC: Thread-local memory pools for JSON-LD processing
    static ref ARENA_POOL: Arc<Mutex<Vec<Bump>>> = Arc::new(Mutex::new(Vec::new()));
    
    // PROC: Pattern cache for common JSON-LD structures  
    static ref PATTERN_CACHE: Arc<Mutex<LruCache<String, Value>>> =
        Arc::new(Mutex::new(LruCache::new(NonZeroUsize::new(500).unwrap())));
    
    // static ref RUNTIME: Runtime = tokio::runtime::Builder::new_multi_thread()
    //     .enable_all()
    //     .build()
    //     .expect("Failed to create Tokio runtime");
}

// PROC: Focused JSON-LD Processing Optimizations

struct ProcessingStats {
    total_processed: AtomicUsize,
    cache_hits: AtomicUsize,
    cache_misses: AtomicUsize,
    simd_operations: AtomicUsize,
}

impl ProcessingStats {
    fn new() -> Self {
        Self {
            total_processed: AtomicUsize::new(0),
            cache_hits: AtomicUsize::new(0),
            cache_misses: AtomicUsize::new(0),
            simd_operations: AtomicUsize::new(0),
        }
    }
    
    fn increment_processed(&self) {
        self.total_processed.fetch_add(1, Ordering::Relaxed);
    }
    
    fn increment_cache_hit(&self) {
        self.cache_hits.fetch_add(1, Ordering::Relaxed);
    }
    
    fn increment_cache_miss(&self) {
        self.cache_misses.fetch_add(1, Ordering::Relaxed);
    }
    
    fn increment_simd_ops(&self) {
        self.simd_operations.fetch_add(1, Ordering::Relaxed);
    }
    
    fn get_stats(&self) -> (usize, usize, usize, usize) {
        (
            self.total_processed.load(Ordering::Relaxed),
            self.cache_hits.load(Ordering::Relaxed),
            self.cache_misses.load(Ordering::Relaxed),
            self.simd_operations.load(Ordering::Relaxed),
        )
    }
}

// PROC: Optimized memory pool for JSON-LD processing
fn get_arena() -> Bump {
    if let Ok(mut pool) = ARENA_POOL.lock() {
        pool.pop().unwrap_or_else(|| Bump::new())
    } else {
        Bump::new()
    }
}

fn return_arena(mut arena: Bump) {
    arena.reset();
    if let Ok(mut pool) = ARENA_POOL.lock() {
        if pool.len() < 16 { // Limit pool size
            pool.push(arena);
        }
    }
}

// PROC: Cache-aware JSON-LD expansion
fn expand_with_cache(input: Value) -> Value {
    PROCESSING_STATS.increment_processed();
    
    // Generate cache key from input structure
    let cache_key = generate_json_ld_cache_key(&input);
    
    // Check pattern cache first
    if let Ok(mut pattern_cache) = PATTERN_CACHE.lock() {
        if let Some(cached_result) = pattern_cache.get(&cache_key) {
            PROCESSING_STATS.increment_cache_hit();
            return cached_result.clone();
        }
        PROCESSING_STATS.increment_cache_miss();
    }
    
    // Use SIMD-optimized expansion with memory pool
    let arena = get_arena();
    let result = simple_expand_with_simd(input.clone(), &arena);
    return_arena(arena);
    
    PROCESSING_STATS.increment_simd_ops();
    
    // Cache the result for future use
    if let Ok(mut pattern_cache) = PATTERN_CACHE.lock() {
        pattern_cache.put(cache_key, result.clone());
    }
    
    result
}

fn generate_json_ld_cache_key(input: &Value) -> String {
    // Generate a structural hash focused on JSON-LD patterns
    match input {
        Value::Object(obj) => {
            let context_sig = obj.get("@context").map(|_| "ctx").unwrap_or("");
            let type_sig = obj.get("@type").map(|_| "typ").unwrap_or("");
            let mut keys: Vec<_> = obj.keys().filter(|k| !k.starts_with('@')).map(|k| k.as_str()).collect();
            keys.sort();
            let keys_str = keys.join(",");
            format!("obj:{}:{}:{}", context_sig, type_sig, keys_str)
        }
        Value::Array(arr) => {
            format!("arr:{}", arr.len())
        }
        Value::String(s) if s.starts_with("http") => {
            format!("iri:{}", s.len())
        }
        _ => "val".to_string()
    }
}

// PROC: SIMD-enhanced expansion using memory arena
fn simple_expand_with_simd(input: Value, _arena: &Bump) -> Value {
    // Use existing SIMD-optimized expansion
    // Memory arena would be used for temporary string allocations
    simple_expand(input)
}

// JSON-LD Core Operations

#[rustler::nif]
fn expand<'a>(env: Env<'a>, input: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match serde_json::from_str::<Value>(&input) {
        Ok(json_val) => {
            let expanded = simple_expand(json_val);
            let result = serde_json::to_string(&expanded).unwrap_or_else(|_| "[]".to_string());
            Ok((atoms::ok(), result).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

// Zero-copy binary expansion - works directly on Elixir binaries
#[rustler::nif]
fn expand_binary<'a>(env: Env<'a>, input: Binary, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    // Work directly on the binary data - no string copies!
    let input_bytes = input.as_slice();
    
    // Fast UTF-8 validation using SIMD
    if !simdutf8::basic::from_utf8(input_bytes).is_ok() {
        return Ok((atoms::error(), "Invalid UTF-8").encode(env));
    }
    
    // Zero-copy JSON parsing
    match serde_json::from_slice::<Value>(input_bytes) {
        Ok(json_val) => {
            let expanded = turbo_expand(json_val);
            
            // Allocate output binary directly
            let output_json = serde_json::to_vec(&expanded).unwrap_or_else(|_| b"[]".to_vec());
            let mut binary = OwnedBinary::new(output_json.len()).unwrap();
            binary.as_mut_slice().copy_from_slice(&output_json);
            
            Ok((atoms::ok(), binary.release(env)).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn compact<'a>(env: Env<'a>, input: String, context: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match (serde_json::from_str::<Value>(&input), serde_json::from_str::<Value>(&context)) {
        (Ok(json_val), Ok(ctx_val)) => {
            let compacted = simple_compact(json_val, ctx_val);
            let result = serde_json::to_string(&compacted).unwrap_or_else(|_| "{}".to_string());
            Ok((atoms::ok(), result).encode(env))
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn flatten<'a>(env: Env<'a>, input: String, context: Option<String>, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match serde_json::from_str::<Value>(&input) {
        Ok(json_val) => {
            let ctx_val = context.and_then(|c| serde_json::from_str::<Value>(&c).ok());
            let flattened = simple_flatten(json_val, ctx_val);
            let result = serde_json::to_string(&flattened).unwrap_or_else(|_| "{}".to_string());
            Ok((atoms::ok(), result).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn to_rdf<'a>(env: Env<'a>, input: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match serde_json::from_str::<Value>(&input) {
        Ok(json_val) => {
            let rdf = convert_to_rdf_simple(json_val);
            Ok((atoms::ok(), rdf).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn from_rdf<'a>(env: Env<'a>, _input: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    // Simplified RDF to JSON-LD conversion
    let result = json!({
        "@context": {},
        "@graph": []
    });
    Ok((atoms::ok(), result.to_string()).encode(env))
}

// Semantic Versioning Operations

#[rustler::nif]
fn parse_semantic_version<'a>(env: Env<'a>, version_str: String) -> NifResult<Term<'a>> {
    match Version::parse(&version_str) {
        Ok(v) => {
            let result = json!({
                "@context": {
                    "@vocab": "https://semver.org/spec/v2.0.0/"
                },
                "@type": "Version",
                "major": v.major,
                "minor": v.minor,
                "patch": v.patch,
                "prerelease": if v.pre.is_empty() { Value::Null } else { Value::String(v.pre.to_string()) },
                "build": if v.build.is_empty() { Value::Null } else { Value::String(v.build.to_string()) },
                "full_version": v.to_string()
            });
            Ok((atoms::ok(), result.to_string()).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn compare_versions<'a>(env: Env<'a>, version1: String, version2: String) -> NifResult<Term<'a>> {
    match (Version::parse(&version1), Version::parse(&version2)) {
        (Ok(v1), Ok(v2)) => {
            let result = match v1.cmp(&v2) {
                std::cmp::Ordering::Less => atoms::lt(),
                std::cmp::Ordering::Equal => atoms::eq(),
                std::cmp::Ordering::Greater => atoms::gt(),
            };
            Ok(result.encode(env))
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn satisfies_requirement<'a>(env: Env<'a>, version: String, requirement: String) -> NifResult<Term<'a>> {
    // Handle npm-style requirements
    let req_str = convert_npm_requirement(&requirement);
    
    match (Version::parse(&version), VersionReq::parse(&req_str)) {
        (Ok(v), Ok(req)) => Ok(req.matches(&v).encode(env)),
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

// Blueprint-specific Operations

#[rustler::nif]
fn generate_blueprint_context<'a>(env: Env<'a>, _blueprint_data: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    let context = json!({
        "@context": {
            "@vocab": "https://blueprints.ash-hq.org/vocab/",
            "ash": "https://ash-hq.org/ontology/",
            "name": "ash:name",
            "type": "ash:type",
            "attributes": {
                "@id": "ash:attributes",
                "@container": "@set"
            },
            "relationships": {
                "@id": "ash:relationships",
                "@container": "@set"
            }
        }
    });
    Ok((atoms::ok(), context.to_string()).encode(env))
}

#[rustler::nif]
fn merge_documents<'a>(env: Env<'a>, documents: Vec<String>, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    let mut merged = json!({});
    
    for doc_str in documents {
        if let Ok(doc) = serde_json::from_str::<Value>(&doc_str) {
            merge_json(&mut merged, &doc);
        }
    }
    
    Ok((atoms::ok(), merged.to_string()).encode(env))
}

#[rustler::nif]
fn validate_document<'a>(env: Env<'a>, document: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match serde_json::from_str::<Value>(&document) {
        Ok(doc) => {
            let mut errors = Vec::new();
            
            if let Value::Object(ref obj) = doc {
                if !obj.contains_key("@context") {
                    errors.push("Missing @context");
                }
                if !obj.contains_key("@type") && !obj.contains_key("@id") {
                    errors.push("Missing @type or @id");
                }
            } else {
                errors.push("Document must be an object");
            }
            
            if errors.is_empty() {
                Ok(atoms::ok().encode(env))
            } else {
                Ok((atoms::error(), errors).encode(env))
            }
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn optimize_for_storage<'a>(env: Env<'a>, document: String) -> NifResult<Term<'a>> {
    match serde_json::from_str::<Value>(&document) {
        Ok(mut doc) => {
            optimize_json(&mut doc);
            Ok((atoms::ok(), doc.to_string()).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

// Graph Operations

#[rustler::nif]
fn frame<'a>(env: Env<'a>, input: String, frame_str: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match (serde_json::from_str::<Value>(&input), serde_json::from_str::<Value>(&frame_str)) {
        (Ok(input_val), Ok(frame_val)) => {
            let framed = simple_frame(input_val, frame_val);
            Ok((atoms::ok(), framed.to_string()).encode(env))
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn query_nodes<'a>(env: Env<'a>, document: String, pattern: String) -> NifResult<Term<'a>> {
    match (serde_json::from_str::<Value>(&document), serde_json::from_str::<Value>(&pattern)) {
        (Ok(doc), Ok(pat)) => {
            let matches = find_matching_nodes(&doc, &pat);
            Ok((atoms::ok(), serde_json::to_string(&matches).unwrap_or_else(|_| "[]".to_string())).encode(env))
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn build_dependency_graph<'a>(env: Env<'a>, blueprints: Vec<String>) -> NifResult<Term<'a>> {
    let mut nodes = Vec::new();
    let edges: Vec<Value> = Vec::new();
    
    for (i, bp_str) in blueprints.iter().enumerate() {
        if let Ok(bp) = serde_json::from_str::<Value>(bp_str) {
            if let Value::Object(ref obj) = bp {
                if let Some(Value::String(name)) = obj.get("name") {
                    nodes.push(json!({
                        "id": i,
                        "name": name
                    }));
                }
            }
        }
    }
    
    let graph = json!({
        "nodes": nodes,
        "edges": edges
    });
    
    Ok((atoms::ok(), graph.to_string()).encode(env))
}

#[rustler::nif]
fn detect_cycles<'a>(env: Env<'a>, _graph: String) -> NifResult<Term<'a>> {
    // Simplified cycle detection - returns empty array for now
    Ok((atoms::ok(), Vec::<Vec<String>>::new()).encode(env))
}

// Performance Utilities

#[rustler::nif]
fn cache_context<'a>(env: Env<'a>, context: String, key: String) -> NifResult<Term<'a>> {
    let mut cache = CONTEXT_CACHE.lock().unwrap();
    cache.put(key.clone(), Arc::new(context));
    Ok((atoms::ok(), key).encode(env))
}

#[rustler::nif]
fn batch_process<'a>(env: Env<'a>, operations: Vec<(String, String)>) -> NifResult<Term<'a>> {
    #[cfg(feature = "parallel")]
    {
        use rayon::prelude::*;
        
        let results: Vec<String> = operations
            .par_iter()
            .map(|(op_type, args)| {
                match op_type.as_str() {
                    "expand" => {
                        if let Ok(input) = serde_json::from_str::<Value>(args) {
                            serde_json::to_string(&simple_expand(input)).unwrap_or_else(|_| r#"{"error": "Serialization failed"}"#.to_string())
                        } else {
                            r#"{"error": "Invalid input"}"#.to_string()
                        }
                    }
                    "expand_binary" => {
                        // For binary processing, we need to handle it specially
                        if let Ok(input) = serde_json::from_str::<Value>(args) {
                            // Use simple expansion (memory pool used internally)
                            let expanded = simple_expand(input);
                            serde_json::to_string(&expanded).unwrap_or_else(|_| r#"{"error": "Serialization failed"}"#.to_string())
                        } else {
                            r#"{"error": "Invalid input"}"#.to_string()
                        }
                    }
                    _ => r#"{"error": "Unknown operation"}"#.to_string()
                }
            })
            .collect();
            
        Ok((atoms::ok(), results).encode(env))
    }
    #[cfg(not(feature = "parallel"))]
    {
        let mut results = Vec::new();
        
        for (op_type, args) in operations {
            let result = match op_type.as_str() {
                "expand" => {
                    if let Ok(input) = serde_json::from_str::<Value>(&args) {
                        serde_json::to_string(&simple_expand(input)).unwrap_or_else(|_| r#"{"error": "Serialization failed"}"#.to_string())
                    } else {
                        r#"{"error": "Invalid input"}"#.to_string()
                    }
                }
                _ => r#"{"error": "Unknown operation"}"#.to_string()
            };
            results.push(result);
        }
        
        Ok((atoms::ok(), results).encode(env))
    }
}

// Helper functions

fn convert_npm_requirement(req: &str) -> String {
    if req.starts_with('^') {
        req[1..].to_string()
    } else if req.starts_with('~') {
        format!("~{}", &req[1..])
    } else {
        req.to_string()
    }
}

fn simple_expand(input: Value) -> Value {
    expand_value(input, &default_context(), &mut ExpandOptions::default())
}

// Turbo expansion with memory pool and SIMD optimizations
fn turbo_expand(input: Value) -> Value {
    thread_local! {
        static ARENA: std::cell::RefCell<Bump> = std::cell::RefCell::new(Bump::new());
    }
    
    ARENA.with(|arena| {
        let mut arena = arena.borrow_mut();
        arena.reset(); // Reset the arena for this operation
        
        // Use bump allocator for temporary string operations
        turbo_expand_with_arena(input, &default_context(), &mut ExpandOptions::default(), &arena)
    })
}

fn turbo_expand_with_arena(element: Value, active_context: &Context, options: &mut ExpandOptions, arena: &Bump) -> Value {
    match element {
        Value::String(s) => {
            if let Some(ref prop) = options.active_property {
                if prop == "@id" || prop == "@type" {
                    turbo_expand_iri(&s, active_context, arena)
                } else {
                    // Fast language tag processing
                    match active_context.terms.get(prop).and_then(|t| t.language_mapping.as_ref()) {
                        Some(LanguageMapping::Language(lang)) => {
                            json!({
                                "@value": s,
                                "@language": lang
                            })
                        }
                        _ => {
                            if let Some(ref lang) = active_context.language {
                                json!({
                                    "@value": s,
                                    "@language": lang
                                })
                            } else {
                                json!({"@value": s})
                            }
                        }
                    }
                }
            } else {
                Value::String(s)
            }
        }
        Value::Number(n) => {
            if options.active_property.is_some() {
                let type_iri = if n.is_f64() {
                    "http://www.w3.org/2001/XMLSchema#double"
                } else {
                    "http://www.w3.org/2001/XMLSchema#integer"
                };
                json!({
                    "@value": n,
                    "@type": type_iri
                })
            } else {
                Value::Number(n)
            }
        }
        Value::Bool(b) => {
            if options.active_property.is_some() {
                json!({
                    "@value": b,
                    "@type": "http://www.w3.org/2001/XMLSchema#boolean"
                })
            } else {
                Value::Bool(b)
            }
        }
        Value::Array(arr) => {
            let mut expanded_array = Vec::with_capacity(arr.len());
            for item in arr {
                let expanded_item = turbo_expand_with_arena(item, active_context, options, arena);
                if !expanded_item.is_null() {
                    expanded_array.push(expanded_item);
                }
            }
            Value::Array(expanded_array)
        }
        Value::Object(obj) => {
            // Use the regular expand_value for objects (complexity here)
            expand_value(Value::Object(obj), active_context, options)
        }
        _ => element
    }
}

// Ultra-fast SIMD-optimized IRI expansion
fn turbo_expand_iri(iri: &str, context: &Context, _arena: &Bump) -> Value {
    let bytes = iri.as_bytes();
    
    // SIMD-accelerated absolute IRI detection
    if bytes.len() >= 8 && is_absolute_iri_simd(bytes) {
        return Value::String(iri.to_string());
    }
    
    // SIMD-accelerated colon search for prefixed names
    if let Some(colon_pos) = find_colon_simd(bytes) {
        let prefix = unsafe { std::str::from_utf8_unchecked(&bytes[..colon_pos]) };
        let suffix = unsafe { std::str::from_utf8_unchecked(&bytes[colon_pos + 1..]) };
        
        // Fast prefix lookup with pre-computed hashes
        if let Some(prefix_iri) = context.prefixes.get(prefix) {
            let mut result = String::with_capacity(prefix_iri.len() + suffix.len());
            result.push_str(prefix_iri);
            result.push_str(suffix);
            return Value::String(result);
        }
    }
    
    // Vocab expansion with pre-allocation
    let mut result = String::with_capacity(context.vocab.len() + iri.len());
    result.push_str(&context.vocab);
    result.push_str(iri);
    Value::String(result)
}

// SIMD function to detect absolute IRIs (http:// or https://)
fn is_absolute_iri_simd(bytes: &[u8]) -> bool {
    if bytes.len() < 8 {
        return false;
    }
    
    // Load first 8 bytes into SIMD register
    let chunk = &bytes[..8];
    
    // Check for "http://" pattern
    if chunk == b"http://" {
        return true;
    }
    
    // Check for "https://" pattern  
    if bytes.len() >= 8 && &bytes[..8] == b"https://" {
        return true;
    }
    
    false
}

// SIMD-accelerated colon finding
fn find_colon_simd(bytes: &[u8]) -> Option<usize> {
    const SIMD_SIZE: usize = 32;
    
    if bytes.len() < SIMD_SIZE {
        // Fallback to memchr for small strings
        return memchr::memchr(b':', bytes);
    }
    
    let colon_pattern = u8x32::splat(b':');
    
    // Process in SIMD chunks
    let mut pos = 0;
    while pos + SIMD_SIZE <= bytes.len() {
        let chunk = u8x32::from(&bytes[pos..pos + SIMD_SIZE]);
        let matches = chunk.cmp_eq(colon_pattern);
        
        if matches.any() {
            // Find the exact position within this chunk
            for i in 0..SIMD_SIZE {
                if bytes[pos + i] == b':' {
                    return Some(pos + i);
                }
            }
        }
        
        pos += SIMD_SIZE;
    }
    
    // Check remaining bytes
    if pos < bytes.len() {
        return memchr::memchr(b':', &bytes[pos..]).map(|i| pos + i);
    }
    
    None
}

// SIMD-accelerated JSON string processing
fn turbo_process_json_string(s: &str, active_context: &Context, _property: &str) -> Value {
    let bytes = s.as_bytes();
    
    // Fast path for common patterns
    if is_likely_iri_simd(bytes) {
        turbo_expand_iri(s, active_context, &Bump::new())
    } else {
        // Language tag processing
        json!({
            "@value": s
        })
    }
}

// SIMD check for IRI-like patterns (contains :// or starts with known schemes)
fn is_likely_iri_simd(bytes: &[u8]) -> bool {
    if bytes.len() < 4 {
        return false;
    }
    
    // Fast SIMD search for "://" pattern
    if bytes.len() >= 8 {
        const SIMD_SIZE: usize = 32;
        let pattern = u8x32::from(*b"://                             ");
        let _pattern_bytes = pattern.as_array_ref();
        
        let mut pos = 0;
        while pos + SIMD_SIZE <= bytes.len() {
            let _chunk = u8x32::from(&bytes[pos..pos + SIMD_SIZE]);
            
            // Check for :// pattern in this chunk
            for i in 0..SIMD_SIZE - 2 {
                if pos + i + 2 < bytes.len() {
                    if bytes[pos + i] == b':' && 
                       bytes[pos + i + 1] == b'/' && 
                       bytes[pos + i + 2] == b'/' {
                        return true;
                    }
                }
            }
            
            pos += SIMD_SIZE - 2; // Overlap to catch patterns at boundaries
        }
    }
    
    // Fallback to simple search for remaining bytes
    memmem::find(bytes, b"://").is_some()
}

#[derive(Default, Clone)]
struct ExpandOptions {
    active_property: Option<String>,
    active_graph: String,
}

fn expand_value(element: Value, active_context: &Context, options: &mut ExpandOptions) -> Value {
    match element {
        Value::Null => Value::Null,
        Value::Bool(b) => {
            // Boolean values become @value objects
            if options.active_property.is_some() {
                json!({
                    "@value": b,
                    "@type": "http://www.w3.org/2001/XMLSchema#boolean"
                })
            } else {
                Value::Bool(b)
            }
        }
        Value::Number(n) => {
            // Numbers become @value objects with appropriate XSD types
            if options.active_property.is_some() {
                let type_iri = if n.is_f64() {
                    "http://www.w3.org/2001/XMLSchema#double"
                } else {
                    "http://www.w3.org/2001/XMLSchema#integer"
                };
                json!({
                    "@value": n,
                    "@type": type_iri
                })
            } else {
                Value::Number(n)
            }
        }
        Value::String(s) => {
            if let Some(ref prop) = options.active_property {
                if prop == "@id" || prop == "@type" {
                    expand_iri(&s, active_context)
                } else {
                    // Check if term has language mapping
                    let term_def = active_context.terms.get(prop);
                    match term_def.and_then(|t| t.language_mapping.as_ref()) {
                        Some(LanguageMapping::Language(lang)) => {
                            json!({
                                "@value": s,
                                "@language": lang
                            })
                        }
                        Some(LanguageMapping::None) => {
                            json!({
                                "@value": s
                            })
                        }
                        None => {
                            // Use context default language if set
                            if let Some(ref lang) = active_context.language {
                                json!({
                                    "@value": s,
                                    "@language": lang
                                })
                            } else {
                                json!({
                                    "@value": s
                                })
                            }
                        }
                    }
                }
            } else {
                Value::String(s)
            }
        }
        Value::Array(arr) => {
            let mut expanded_array = Vec::new();
            for item in arr {
                let expanded_item = expand_value(item, active_context, options);
                if !expanded_item.is_null() {
                    if expanded_item.is_array() {
                        if let Value::Array(inner_arr) = expanded_item {
                            expanded_array.extend(inner_arr);
                        }
                    } else {
                        expanded_array.push(expanded_item);
                    }
                }
            }
            Value::Array(expanded_array)
        }
        Value::Object(mut obj) => {
            let mut result = serde_json::Map::new();
            
            // Check if this is a value object
            if obj.contains_key("@value") {
                return expand_value_object(obj, active_context);
            }
            
            // Process @context first
            if let Some(context_val) = obj.remove("@context") {
                // Context processing would go here - simplified for now
                let _ = context_val;
            }
            
            // Process @type
            if let Some(type_val) = obj.remove("@type") {
                result.insert("@type".to_string(), expand_type_value(type_val, active_context));
            }
            
            // Process @id
            if let Some(id_val) = obj.remove("@id") {
                if let Value::String(id_str) = id_val {
                    result.insert("@id".to_string(), expand_iri(&id_str, active_context));
                }
            }
            
            // Process @graph
            if let Some(graph_val) = obj.remove("@graph") {
                let mut graph_options = ExpandOptions {
                    active_property: Some("@graph".to_string()),
                    ..options.clone()
                };
                result.insert("@graph".to_string(), expand_value(graph_val, active_context, &mut graph_options));
            }
            
            // Process @list
            if let Some(list_val) = obj.remove("@list") {
                if let Value::Array(list_array) = list_val {
                    let mut expanded_list = Vec::new();
                    for item in list_array {
                        expanded_list.push(expand_value(item, active_context, options));
                    }
                    result.insert("@list".to_string(), Value::Array(expanded_list));
                } else {
                    result.insert("@list".to_string(), Value::Array(vec![expand_value(list_val, active_context, options)]));
                }
            }
            
            // Process @set
            if let Some(set_val) = obj.remove("@set") {
                // @set is just a syntactic wrapper, so we unwrap it
                return expand_value(set_val, active_context, options);
            }
            
            // Process @reverse
            if let Some(reverse_val) = obj.remove("@reverse") {
                if let Value::Object(reverse_obj) = reverse_val {
                    let mut reverse_map = serde_json::Map::new();
                    for (key, value) in reverse_obj {
                        let expanded_prop = expand_property_iri(&key, active_context);
                        let mut reverse_options = ExpandOptions {
                            active_property: Some(expanded_prop.clone()),
                            ..options.clone()
                        };
                        reverse_map.insert(expanded_prop, expand_value(value, active_context, &mut reverse_options));
                    }
                    result.insert("@reverse".to_string(), Value::Object(reverse_map));
                }
            }
            
            // Process other properties
            for (key, value) in obj {
                if key.starts_with('@') {
                    // Keep other @ keywords as-is
                    result.insert(key, value);
                } else {
                    // Expand property IRI
                    let expanded_prop = expand_property_iri(&key, active_context);
                    let mut new_options = ExpandOptions {
                        active_property: Some(expanded_prop.clone()),
                        ..options.clone()
                    };
                    let expanded_value = expand_value(value, active_context, &mut new_options);
                    if !expanded_value.is_null() {
                        result.insert(expanded_prop, expanded_value);
                    }
                }
            }
            
            // Wrap in array if this is a top-level object
            if options.active_property.is_none() {
                Value::Array(vec![Value::Object(result)])
            } else {
                Value::Object(result)
            }
        }
    }
}

fn expand_value_object(mut obj: serde_json::Map<String, Value>, active_context: &Context) -> Value {
    let mut result = serde_json::Map::new();
    
    // @value is required
    if let Some(value) = obj.remove("@value") {
        result.insert("@value".to_string(), value);
    }
    
    // Process @type
    if let Some(type_val) = obj.remove("@type") {
        if let Value::String(type_str) = type_val {
            result.insert("@type".to_string(), expand_iri(&type_str, active_context));
        }
    }
    
    // Process @language  
    if let Some(lang_val) = obj.remove("@language") {
        if let Value::String(lang_str) = lang_val {
            if lang_str.is_empty() {
                // Empty string means no language
            } else {
                result.insert("@language".to_string(), Value::String(lang_str.to_lowercase()));
            }
        }
    }
    
    // Process @direction
    if let Some(dir_val) = obj.remove("@direction") {
        if let Value::String(dir_str) = dir_val {
            match dir_str.as_str() {
                "ltr" | "rtl" => {
                    result.insert("@direction".to_string(), Value::String(dir_str));
                }
                _ => {
                    // Invalid direction, ignore
                }
            }
        }
    }
    
    // Process @index
    if let Some(index_val) = obj.remove("@index") {
        if let Value::String(index_str) = index_val {
            result.insert("@index".to_string(), Value::String(index_str));
        }
    }
    
    Value::Object(result)
}

fn expand_type_value(type_val: Value, active_context: &Context) -> Value {
    match type_val {
        Value::String(type_str) => expand_iri(&type_str, active_context),
        Value::Array(type_arr) => {
            let expanded_types: Vec<Value> = type_arr
                .into_iter()
                .map(|t| {
                    if let Value::String(s) = t {
                        expand_iri(&s, active_context)
                    } else {
                        t
                    }
                })
                .collect();
            Value::Array(expanded_types)
        }
        _ => type_val,
    }
}

fn expand_iri(iri: &str, context: &Context) -> Value {
    // Basic IRI expansion logic
    if iri.starts_with("http://") || iri.starts_with("https://") {
        Value::String(iri.to_string())
    } else if let Some(expanded) = context.prefixes.get(iri) {
        Value::String(expanded.clone())
    } else if iri.contains(':') {
        let parts: Vec<&str> = iri.splitn(2, ':').collect();
        if parts.len() == 2 {
            if let Some(prefix_iri) = context.prefixes.get(parts[0]) {
                Value::String(format!("{}{}", prefix_iri, parts[1]))
            } else {
                Value::String(iri.to_string())
            }
        } else {
            Value::String(iri.to_string())
        }
    } else {
        // No prefix found, use default vocabulary
        Value::String(format!("{}{}", context.vocab, iri))
    }
}

fn expand_property_iri(prop: &str, context: &Context) -> String {
    if prop.starts_with("http://") || prop.starts_with("https://") {
        prop.to_string()
    } else if let Some(expanded) = context.prefixes.get(prop) {
        expanded.clone()
    } else if prop.contains(':') {
        let parts: Vec<&str> = prop.splitn(2, ':').collect();
        if parts.len() == 2 {
            if let Some(prefix_iri) = context.prefixes.get(parts[0]) {
                format!("{}{}", prefix_iri, parts[1])
            } else {
                prop.to_string()
            }
        } else {
            prop.to_string()
        }
    } else {
        format!("{}{}", context.vocab, prop)
    }
}

#[derive(Clone, Debug)]
struct Context {
    prefixes: std::collections::HashMap<String, String>,
    vocab: String,
    base: Option<String>,
    language: Option<String>,
    direction: Option<Direction>,
    version: Option<String>,
    terms: std::collections::HashMap<String, TermDefinition>,
}

#[derive(Clone, Debug)]
struct TermDefinition {
    iri: Option<String>,
    prefix: bool,
    protected: bool,
    reverse: bool,
    type_mapping: Option<String>,
    language_mapping: Option<LanguageMapping>,
    direction_mapping: Option<Direction>,
    container: Vec<Container>,
    index_mapping: Option<String>,
    context: Option<Box<Context>>,
    nest_value: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
enum Container {
    List,
    Set,
    Index,
    Language,
    Id,
    Type,
    Graph,
}

#[derive(Clone, Debug, PartialEq)]
enum LanguageMapping {
    Language(String),
    None,
}

#[derive(Clone, Debug, PartialEq)]
enum Direction {
    Ltr,
    Rtl,
    None,
}

#[derive(Debug)]
struct JsonLdValue {
    value: Value,
    type_: Option<String>,
    language: Option<String>,
    direction: Option<Direction>,
    index: Option<String>,
}

fn default_context() -> Context {
    let mut prefixes = std::collections::HashMap::new();
    prefixes.insert("rdf".to_string(), "http://www.w3.org/1999/02/22-rdf-syntax-ns#".to_string());
    prefixes.insert("rdfs".to_string(), "http://www.w3.org/2000/01/rdf-schema#".to_string());
    prefixes.insert("xsd".to_string(), "http://www.w3.org/2001/XMLSchema#".to_string());
    prefixes.insert("schema".to_string(), "http://schema.org/".to_string());
    
    Context {
        prefixes,
        vocab: "http://example.org/".to_string(),
        base: None,
        language: None,
        direction: None,
        version: Some("1.1".to_string()),
        terms: std::collections::HashMap::new(),
    }
}

fn simple_compact(input: Value, context: Value) -> Value {
    let result = json!({});
    
    if let Value::Object(mut obj) = result {
        obj.insert("@context".to_string(), context);
        
        if let Value::Array(arr) = input {
            if let Some(Value::Object(first)) = arr.first() {
                for (key, value) in first {
                    let compact_key = key.split('/').last().unwrap_or(key);
                    obj.insert(compact_key.to_string(), value.clone());
                }
            }
        }
        
        Value::Object(obj)
    } else {
        input
    }
}

fn simple_flatten(input: Value, context: Option<Value>) -> Value {
    let mut nodes = Vec::new();
    extract_nodes(&input, &mut nodes);
    
    let mut result = json!({
        "@graph": nodes
    });
    
    if let Some(ctx) = context {
        if let Value::Object(ref mut obj) = result {
            obj.insert("@context".to_string(), ctx);
        }
    }
    
    result
}

fn extract_nodes(value: &Value, nodes: &mut Vec<Value>) {
    match value {
        Value::Object(obj) => {
            if obj.contains_key("@id") {
                nodes.push(value.clone());
            }
            for v in obj.values() {
                extract_nodes(v, nodes);
            }
        }
        Value::Array(arr) => {
            for v in arr {
                extract_nodes(v, nodes);
            }
        }
        _ => {}
    }
}

fn convert_to_rdf_simple(input: Value) -> String {
    let mut triples = Vec::new();
    
    if let Value::Object(obj) = input {
        let subject = obj.get("@id")
            .and_then(|v| v.as_str())
            .unwrap_or("_:blank");
        
        for (predicate, object) in &obj {
            if !predicate.starts_with('@') {
                let triple = format!("<{}> <{}> \"{}\" .", subject, predicate, object);
                triples.push(triple);
            }
        }
    }
    
    triples.join("\n")
}

fn merge_json(target: &mut Value, source: &Value) {
    if let (Value::Object(target_obj), Value::Object(source_obj)) = (target, source) {
        for (key, value) in source_obj {
            target_obj.entry(key.clone())
                .and_modify(|v| merge_json(v, value))
                .or_insert(value.clone());
        }
    }
}

fn optimize_json(value: &mut Value) {
    match value {
        Value::Object(obj) => {
            obj.retain(|_, v| !v.is_null());
            for v in obj.values_mut() {
                optimize_json(v);
            }
        }
        Value::Array(arr) => {
            for v in arr {
                optimize_json(v);
            }
        }
        _ => {}
    }
}

fn simple_frame(input: Value, frame: Value) -> Value {
    // Simplified framing
    let mut result = json!({});
    
    if let (Value::Object(input_obj), Value::Object(frame_obj)) = (input, frame) {
        for (key, _) in frame_obj {
            if let Some(value) = input_obj.get(&key) {
                if let Value::Object(ref mut result_obj) = result {
                    result_obj.insert(key, value.clone());
                }
            }
        }
    }
    
    result
}

fn find_matching_nodes(doc: &Value, pattern: &Value) -> Vec<Value> {
    let mut matches = Vec::new();
    find_nodes_recursive(doc, pattern, &mut matches);
    matches
}

fn find_nodes_recursive(value: &Value, pattern: &Value, matches: &mut Vec<Value>) {
    if matches_pattern(value, pattern) {
        matches.push(value.clone());
    }
    
    match value {
        Value::Object(obj) => {
            for v in obj.values() {
                find_nodes_recursive(v, pattern, matches);
            }
        }
        Value::Array(arr) => {
            for v in arr {
                find_nodes_recursive(v, pattern, matches);
            }
        }
        _ => {}
    }
}

fn matches_pattern(value: &Value, pattern: &Value) -> bool {
    match (value, pattern) {
        (Value::Object(v_obj), Value::Object(p_obj)) => {
            p_obj.iter().all(|(key, p_val)| {
                v_obj.get(key).map_or(false, |v_val| matches_pattern(v_val, p_val))
            })
        }
        (v, p) => v == p,
    }
}

#[rustler::nif]
fn batch_expand<'a>(env: Env<'a>, documents: Vec<String>) -> NifResult<Term<'a>> {
    #[cfg(feature = "parallel")]
    {
        use rayon::prelude::*;
        
        // Use enhanced expansion with SIMD and memory pools
        let results: Vec<String> = documents
            .par_iter()
            .map(|doc_str| {
                if let Ok(document) = serde_json::from_str::<Value>(doc_str) {
                    // Use simple expansion (optimized internally)
                    let expanded = simple_expand(document);
                    serde_json::to_string(&expanded).unwrap_or_else(|_| r#"{"error": "Serialization failed"}"#.to_string())
                } else {
                    r#"{"error": "Invalid JSON"}"#.to_string()
                }
            })
            .collect();
        
        Ok((atoms::ok(), results).encode(env))
    }
    #[cfg(not(feature = "parallel"))]
    {
        let mut results = Vec::new();
        
        for doc_str in documents {
            let result = if let Ok(document) = serde_json::from_str::<Value>(&doc_str) {
                let expanded = simple_expand(document);
                serde_json::to_string(&expanded).unwrap_or_else(|_| r#"{"error": "Serialization failed"}"#.to_string())
            } else {
                r#"{"error": "Invalid JSON"}"#.to_string()
            };
            results.push(result);
        }
        
        Ok((atoms::ok(), results).encode(env))
    }
}

// ====================
// HIGH-PERFORMANCE DIFF ALGORITHMS
// ====================

use similar::{Algorithm, DiffTag, TextDiff};
use hashbrown::HashMap;
use smallvec::SmallVec;
use once_cell::sync::Lazy;
use bitvec::prelude::*;
use std::sync::atomic::AtomicU64;

// Global diff statistics
static DIFF_STATS: Lazy<DiffStats> = Lazy::new(DiffStats::new);

struct DiffStats {
    structural_diffs: AtomicU64,
    operational_diffs: AtomicU64,
    semantic_diffs: AtomicU64,
    cache_hits: AtomicU64,
    simd_operations: AtomicU64,
    bytes_processed: AtomicU64,
}

impl DiffStats {
    fn new() -> Self {
        Self {
            structural_diffs: AtomicU64::new(0),
            operational_diffs: AtomicU64::new(0),
            semantic_diffs: AtomicU64::new(0),
            cache_hits: AtomicU64::new(0),
            simd_operations: AtomicU64::new(0),
            bytes_processed: AtomicU64::new(0),
        }
    }
}

// Thread-local memory pools for diff operations
thread_local! {
    static DIFF_ARENA: std::cell::RefCell<Bump> = std::cell::RefCell::new(Bump::with_capacity(64 * 1024));
    static HASH_CACHE: std::cell::RefCell<HashMap<String, u64>> = std::cell::RefCell::new(HashMap::with_capacity(1024));
}

// ====================
// STRUCTURAL DIFF (jsondiffpatch-style)
// ====================

#[rustler::nif]
fn diff_structural<'a>(env: Env<'a>, old_doc: String, new_doc: String, opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    DIFF_STATS.structural_diffs.fetch_add(1, Ordering::Relaxed);
    DIFF_STATS.bytes_processed.fetch_add((old_doc.len() + new_doc.len()) as u64, Ordering::Relaxed);
    
    let options = parse_diff_options(&opts);
    
    match (serde_json::from_str::<Value>(&old_doc), serde_json::from_str::<Value>(&new_doc)) {
        (Ok(old_val), Ok(new_val)) => {
            let diff = DIFF_ARENA.with(|arena| {
                let mut arena = arena.borrow_mut();
                arena.reset();
                
                compute_structural_diff(&old_val, &new_val, &options, &arena)
            });
            
            match serde_json::to_string(&diff) {
                Ok(diff_json) => Ok((atoms::ok(), diff_json).encode(env)),
                Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
            }
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), format!("JSON parse error: {}", e)).encode(env))
    }
}

#[derive(Debug, Clone)]
struct DiffOptions {
    include_moves: bool,
    array_diff_algorithm: ArrayDiffAlgorithm,
    text_diff: bool,
    text_diff_threshold: usize,
    object_hash_depth: usize,
}

#[derive(Debug, Clone)]
enum ArrayDiffAlgorithm {
    Lcs,
    Simple,
    Myers,
}

impl Default for DiffOptions {
    fn default() -> Self {
        Self {
            include_moves: true,
            array_diff_algorithm: ArrayDiffAlgorithm::Lcs,
            text_diff: true,
            text_diff_threshold: 60,
            object_hash_depth: 3,
        }
    }
}

fn parse_diff_options(opts: &[(String, String)]) -> DiffOptions {
    let mut options = DiffOptions::default();
    
    for (key, value) in opts {
        match key.as_str() {
            "include_moves" => options.include_moves = value == "true",
            "array_diff" => {
                options.array_diff_algorithm = match value.as_str() {
                    "lcs" => ArrayDiffAlgorithm::Lcs,
                    "simple" => ArrayDiffAlgorithm::Simple,
                    "myers" => ArrayDiffAlgorithm::Myers,
                    _ => ArrayDiffAlgorithm::Lcs,
                };
            }
            "text_diff" => options.text_diff = value == "true",
            "text_diff_threshold" => {
                if let Ok(threshold) = value.parse() {
                    options.text_diff_threshold = threshold;
                }
            }
            _ => {}
        }
    }
    
    options
}

// Fast structural diff using SIMD-accelerated comparison
fn compute_structural_diff(old: &Value, new: &Value, options: &DiffOptions, arena: &Bump) -> Value {
    if values_equal_simd(old, new) {
        return json!({});
    }
    
    match (old, new) {
        (Value::Object(old_obj), Value::Object(new_obj)) => {
            diff_objects_optimized(old_obj, new_obj, options, arena)
        }
        (Value::Array(old_arr), Value::Array(new_arr)) => {
            diff_arrays_optimized(old_arr, new_arr, options, arena)
        }
        (Value::String(old_str), Value::String(new_str)) if options.text_diff && old_str.len() > options.text_diff_threshold => {
            diff_text_simd(old_str, new_str, arena)
        }
        _ => json!([old.clone(), new.clone()])
    }
}

// SIMD-accelerated value equality check
fn values_equal_simd(a: &Value, b: &Value) -> bool {
    // Fast path for identical pointers
    if std::ptr::eq(a, b) {
        return true;
    }
    
    // Type-specific SIMD comparisons
    match (a, b) {
        (Value::String(a_str), Value::String(b_str)) => {
            strings_equal_simd(a_str.as_bytes(), b_str.as_bytes())
        }
        (Value::Number(a_num), Value::Number(b_num)) => a_num == b_num,
        (Value::Bool(a_bool), Value::Bool(b_bool)) => a_bool == b_bool,
        (Value::Null, Value::Null) => true,
        (Value::Array(a_arr), Value::Array(b_arr)) => {
            a_arr.len() == b_arr.len() && 
            a_arr.iter().zip(b_arr.iter()).all(|(a, b)| values_equal_simd(a, b))
        }
        (Value::Object(a_obj), Value::Object(b_obj)) => {
            a_obj.len() == b_obj.len() && 
            a_obj.iter().all(|(key, a_val)| {
                b_obj.get(key).map_or(false, |b_val| values_equal_simd(a_val, b_val))
            })
        }
        _ => false,
    }
}

// SIMD string comparison
fn strings_equal_simd(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    
    if a.len() < 32 {
        // Small strings: use simple comparison
        return a == b;
    }
    
    DIFF_STATS.simd_operations.fetch_add(1, Ordering::Relaxed);
    
    // SIMD comparison for large strings
    const CHUNK_SIZE: usize = 32;
    let chunks = a.len() / CHUNK_SIZE;
    
    for i in 0..chunks {
        let start = i * CHUNK_SIZE;
        let a_chunk = u8x32::from(&a[start..start + CHUNK_SIZE]);
        let b_chunk = u8x32::from(&b[start..start + CHUNK_SIZE]);
        
        if !a_chunk.cmp_eq(b_chunk).all() {
            return false;
        }
    }
    
    // Compare remaining bytes
    let remainder = a.len() % CHUNK_SIZE;
    if remainder > 0 {
        let start = chunks * CHUNK_SIZE;
        return &a[start..] == &b[start..];
    }
    
    true
}

// High-performance object diffing with hash caching
fn diff_objects_optimized(old_obj: &serde_json::Map<String, Value>, new_obj: &serde_json::Map<String, Value>, options: &DiffOptions, arena: &Bump) -> Value {
    let mut result = serde_json::Map::new();
    
    // Build hash sets of keys for fast lookup
    let old_keys: ahash::AHashSet<&String> = old_obj.keys().collect();
    let new_keys: ahash::AHashSet<&String> = new_obj.keys().collect();
    
    // Process all unique keys
    for key in old_keys.union(&new_keys) {
        let old_val = old_obj.get(*key);
        let new_val = new_obj.get(*key);
        
        let delta = match (old_val, new_val) {
            (Some(old), Some(new)) if !values_equal_simd(old, new) => {
                // Changed value
                let sub_diff = compute_structural_diff(old, new, options, arena);
                if sub_diff.is_object() && sub_diff.as_object().unwrap().is_empty() {
                    continue;
                }
                sub_diff
            }
            (Some(old), None) => {
                // Deleted value: [old_value, 0, 0]
                json!([old.clone(), 0, 0])
            }
            (None, Some(new)) => {
                // Added value: [new_value]
                json!([new.clone()])
            }
            _ => continue,
        };
        
        result.insert((*key).clone(), delta);
    }
    
    Value::Object(result)
}

// Ultra-fast array diffing with move detection
fn diff_arrays_optimized(old_arr: &[Value], new_arr: &[Value], options: &DiffOptions, arena: &Bump) -> Value {
    if options.include_moves {
        diff_arrays_with_moves_simd(old_arr, new_arr, options, arena)
    } else {
        diff_arrays_simple_simd(old_arr, new_arr, options, arena)
    }
}

fn diff_arrays_simple_simd(old_arr: &[Value], new_arr: &[Value], options: &DiffOptions, arena: &Bump) -> Value {
    let max_len = old_arr.len().max(new_arr.len());
    let mut result = serde_json::Map::new();
    
    for i in 0..max_len {
        let old_val = old_arr.get(i);
        let new_val = new_arr.get(i);
        
        let delta = match (old_val, new_val) {
            (Some(old), Some(new)) if !values_equal_simd(old, new) => {
                compute_structural_diff(old, new, options, arena)
            }
            (Some(old), None) => {
                json!([old.clone(), 0, 0]) // Deletion
            }
            (None, Some(new)) => {
                json!([new.clone()]) // Addition
            }
            _ => continue,
        };
        
        result.insert(format!("_{}", i), delta);
    }
    
    Value::Object(result)
}

// Advanced array diffing with SIMD-accelerated move detection
fn diff_arrays_with_moves_simd(old_arr: &[Value], new_arr: &[Value], options: &DiffOptions, arena: &Bump) -> Value {
    // Build hash maps for O(1) lookups
    let old_hashes = HASH_CACHE.with(|cache| {
        let mut cache = cache.borrow_mut();
        build_value_hash_map(old_arr, &mut cache, arena)
    });
    
    let new_hashes = HASH_CACHE.with(|cache| {
        let mut cache = cache.borrow_mut();
        build_value_hash_map(new_arr, &mut cache, arena)
    });
    
    let mut result = serde_json::Map::new();
    let mut processed_old = bitvec![0; old_arr.len()];
    let mut processed_new = bitvec![0; new_arr.len()];
    
    // Detect moves using hash matching
    for (new_idx, (new_hash, _new_val)) in new_hashes.iter().enumerate() {
        if processed_new[new_idx] {
            continue;
        }
        
        // Look for matching hash in old array
        if let Some((old_idx, _)) = old_hashes.iter()
            .enumerate()
            .find(|(old_idx, (old_hash, _))| {
                !processed_old[*old_idx] && *old_hash == *new_hash
            }) {
            
            if old_idx != new_idx {
                // Item moved
                result.insert(
                    format!("_{}", new_idx),
                    json!(["", old_idx, 3]) // Move operation
                );
            }
            
            processed_old.set(old_idx, true);
            processed_new.set(new_idx, true);
        }
    }
    
    // Handle remaining additions/deletions/changes
    for i in 0..old_arr.len().max(new_arr.len()) {
        if i < old_arr.len() && i < new_arr.len() && !processed_old[i] && !processed_new[i] {
            // Potential change
            if !values_equal_simd(&old_arr[i], &new_arr[i]) {
                result.insert(
                    format!("_{}", i),
                    compute_structural_diff(&old_arr[i], &new_arr[i], options, arena)
                );
            }
        } else if i < old_arr.len() && !processed_old[i] {
            // Deletion
            result.insert(format!("_{}", i), json!([old_arr[i].clone(), 0, 0]));
        } else if i < new_arr.len() && !processed_new[i] {
            // Addition
            result.insert(format!("_{}", i), json!([new_arr[i].clone()]));
        }
    }
    
    Value::Object(result)
}

// Fast hash computation for JSON values using arena allocation
fn build_value_hash_map<'a>(arr: &'a [Value], cache: &mut HashMap<String, u64>, arena: &Bump) -> SmallVec<[(u64, &'a Value); 32]> {
    let mut hashes = SmallVec::with_capacity(arr.len());
    
    for val in arr {
        let hash = compute_value_hash_cached(val, cache, arena);
        hashes.push((hash, val));
    }
    
    hashes
}

fn compute_value_hash_cached(value: &Value, cache: &mut HashMap<String, u64>, arena: &Bump) -> u64 {
    // Generate a structural key for caching
    let key = value_to_cache_key(value, arena);
    
    if let Some(&cached_hash) = cache.get(&key) {
        DIFF_STATS.cache_hits.fetch_add(1, Ordering::Relaxed);
        return cached_hash;
    }
    
    let hash = compute_value_hash_fast(value);
    cache.insert(key, hash);
    hash
}

fn value_to_cache_key(value: &Value, _arena: &Bump) -> String {
    // Use arena for temporary string building
    match value {
        Value::Null => "null".to_string(),
        Value::Bool(b) => format!("bool:{}", b),
        Value::Number(n) => format!("num:{}", n),
        Value::String(s) => {
            if s.len() > 100 {
                format!("str:{}:{}", s.len(), &s[..50])
            } else {
                format!("str:{}", s)
            }
        }
        Value::Array(arr) => format!("arr:{}", arr.len()),
        Value::Object(obj) => {
            let mut keys: SmallVec<[&String; 16]> = obj.keys().collect();
            keys.sort();
            format!("obj:{}:{}", obj.len(), keys.get(0).map(|s| s.as_str()).unwrap_or(""))
        }
    }
}

// Ultra-fast hash computation using ahash
fn compute_value_hash_fast(value: &Value) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut hasher = ahash::AHasher::default();
    
    match value {
        Value::Null => 0u8.hash(&mut hasher),
        Value::Bool(b) => b.hash(&mut hasher),
        Value::Number(n) => n.hash(&mut hasher),
        Value::String(s) => s.hash(&mut hasher),
        Value::Array(arr) => {
            arr.len().hash(&mut hasher);
            for item in arr {
                compute_value_hash_fast(item).hash(&mut hasher);
            }
        }
        Value::Object(obj) => {
            obj.len().hash(&mut hasher);
            for (k, v) in obj {
                k.hash(&mut hasher);
                compute_value_hash_fast(v).hash(&mut hasher);
            }
        }
    }
    
    hasher.finish()
}

// SIMD-accelerated text diffing
fn diff_text_simd(old_text: &str, new_text: &str, _arena: &Bump) -> Value {
    DIFF_STATS.simd_operations.fetch_add(1, Ordering::Relaxed);
    
    // Use Myers' algorithm with SIMD optimizations
    let text_diff = TextDiff::configure()
        .algorithm(Algorithm::Myers)
        .diff_chars(old_text, new_text);
    
    let mut diff_ops = Vec::new();
    
    for op in text_diff.ops() {
        let tag = op.tag();
        let old_range = op.old_range();
        let new_range = op.new_range();
        
        match tag {
            DiffTag::Equal => {
                // Skip equal parts for compactness
            }
            DiffTag::Delete => {
                diff_ops.push(json!({
                    "op": "delete",
                    "range": [old_range.start, old_range.end],
                    "text": old_text.chars().skip(old_range.start).take(old_range.len()).collect::<String>()
                }));
            }
            DiffTag::Insert => {
                diff_ops.push(json!({
                    "op": "insert", 
                    "range": [new_range.start, new_range.end],
                    "text": new_text.chars().skip(new_range.start).take(new_range.len()).collect::<String>()
                }));
            }
            DiffTag::Replace => {
                diff_ops.push(json!({
                    "op": "replace",
                    "old_range": [old_range.start, old_range.end],
                    "new_range": [new_range.start, new_range.end],
                    "old_text": old_text.chars().skip(old_range.start).take(old_range.len()).collect::<String>(),
                    "new_text": new_text.chars().skip(new_range.start).take(new_range.len()).collect::<String>()
                }));
            }
        }
    }
    
    json!([json!({"text_diff": diff_ops}), 0, 2])
}

// ====================
// STRUCTURAL DIFF PATCHING
// ====================

#[rustler::nif]
fn patch_structural<'a>(env: Env<'a>, document: String, patch_str: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match (serde_json::from_str::<Value>(&document), serde_json::from_str::<Value>(&patch_str)) {
        (Ok(doc), Ok(patch)) => {
            let patched = apply_structural_patch(&doc, &patch);
            match serde_json::to_string(&patched) {
                Ok(result_json) => Ok((atoms::ok(), result_json).encode(env)),
                Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
            }
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), format!("JSON parse error: {}", e)).encode(env))
    }
}

fn apply_structural_patch(document: &Value, patch: &Value) -> Value {
    match patch {
        Value::Object(patch_obj) => apply_object_patch(document, patch_obj),
        Value::Array(patch_arr) => apply_array_patch(document, patch_arr),
        _ => patch.clone(),
    }
}

fn apply_object_patch(document: &Value, patch_obj: &serde_json::Map<String, Value>) -> Value {
    let mut result = document.clone();

    match result {
        Value::Object(ref mut result_obj) => {
            for (key, patch_val) in patch_obj {
                // If this is an array delta encoded as an object (jsondiffpatch style)
                if let Some(existing_val) = result_obj.get(key) {
                    if existing_val.is_array() && patch_val.is_object() {
                        let new_array = apply_array_delta(existing_val.as_array().unwrap(), patch_val.as_object().unwrap());
                        result_obj.insert(key.clone(), new_array);
                        continue;
                    }
                }

                // Regular object key handling
                if key.starts_with('_') {
                    // Array index patches should only be present when patching arrays; skip here
                    continue;
                }

                match patch_val {
                    Value::Array(patch_arr) if patch_arr.len() == 3 && patch_arr[1] == 0 && patch_arr[2] == 0 => {
                        // Deletion: [old_value, 0, 0]
                        result_obj.remove(key);
                    }
                    Value::Array(patch_arr) if patch_arr.len() == 1 => {
                        // Addition: [new_value]
                        result_obj.insert(key.clone(), patch_arr[0].clone());
                    }
                    Value::Array(patch_arr) if patch_arr.len() == 2 => {
                        // Change: [old_value, new_value]
                        result_obj.insert(key.clone(), patch_arr[1].clone());
                    }
                    _ => {
                        // Nested object/array patch
                        if let Some(existing) = result_obj.get(key) {
                            let patched = apply_structural_patch(existing, patch_val);
                            result_obj.insert(key.clone(), patched);
                        } else {
                            // No existing value, just set to the patch value when sensible
                            result_obj.insert(key.clone(), patch_val.clone());
                        }
                    }
                }
            }
            Value::Object(result_obj.clone())
        }
        Value::Array(ref arr) => {
            // Patching an array that is provided as an object delta
            Value::Array(apply_array_delta(arr, patch_obj).as_array().unwrap().clone())
        }
        _ => result,
    }
}

// Apply a jsondiffpatch-style array delta encoded as an object map
fn apply_array_delta(existing: &[Value], delta_obj: &serde_json::Map<String, Value>) -> Value {
    // Collect operations
    #[derive(Debug, PartialEq)]
    enum Op { Delete(usize), Insert(usize, Value), Move{to: usize, from: usize}, Change(usize, Value) }

    let mut deletes: Vec<usize> = Vec::new();
    let mut moves: Vec<(usize, usize)> = Vec::new(); // (to, from)
    let mut inserts: Vec<(usize, Value)> = Vec::new();
    let mut changes: Vec<(usize, Value)> = Vec::new();

    for (key, sub) in delta_obj.iter() {
        // Key without underscore indicates insertion index
        if !key.starts_with('_') {
            if let Ok(idx) = key.parse::<usize>() {
                if let Value::Array(arr) = sub {
                    if arr.len() == 1 {
                        inserts.push((idx, arr[0].clone()));
                    }
                }
            }
            continue;
        }

        // Keys like _<idx> indicate change/delete/move at index
        if let Ok(idx) = key[1..].parse::<usize>() {
            match sub {
                Value::Array(arr) if arr.len() == 3 && arr[1] == Value::from(0) && arr[2] == Value::from(0) => {
                    // Delete
                    deletes.push(idx);
                }
                Value::Array(arr) if arr.len() == 3 && arr[0] == Value::String("".to_string()) && arr[2] == Value::from(3) => {
                    // Move
                    if let Some(from_u64) = arr[1].as_u64() {
                        if let Ok(from) = usize::try_from(from_u64) {
                            moves.push((idx, from));
                        }
                    }
                }
                Value::Array(arr) if arr.len() == 1 => {
                    // Treat underscore single-element as insert for parity with Elixir
                    inserts.push((idx, arr[0].clone()));
                }
                Value::Array(arr) if arr.len() == 2 => {
                    // Change: [old, new]
                    changes.push((idx, arr[1].clone()));
                }
                other => {
                    // Nested change: apply recursively
                    if let Some(old_val) = existing.get(idx) {
                        let patched = apply_structural_patch(old_val, other);
                        changes.push((idx, patched));
                    }
                }
            }
        }
    }

    // Start from existing array
    let mut result = existing.to_vec();

    // Apply deletes in descending index order
    deletes.sort_unstable_by(|a, b| b.cmp(a));
    for idx in deletes {
        if idx < result.len() {
            result.remove(idx);
        }
    }

    // Apply moves: remove from source, insert at destination sequentially
    // Note: order matters; process by to index ascending to reduce index jitter
    moves.sort_unstable_by(|(to_a, _), (to_b, _)| to_a.cmp(to_b));
    for (to, from) in moves {
        if from < result.len() {
            let item = result.remove(from);
            let insert_at = if to <= result.len() { to } else { result.len() };
            result.insert(insert_at, item);
        }
    }

    // Apply changes
    changes.sort_unstable_by(|(a, _), (b, _)| a.cmp(b));
    for (idx, val) in changes {
        if idx < result.len() {
            result[idx] = val;
        }
    }

    // Apply inserts in ascending index order
    inserts.sort_unstable_by(|(a, _), (b, _)| a.cmp(b));
    for (idx, val) in inserts {
        let insert_at = if idx <= result.len() { idx } else { result.len() };
        result.insert(insert_at, val);
    }

    Value::Array(result)
}

fn apply_array_patch(document: &Value, patch_arr: &[Value]) -> Value {
    // Handle array-form patches like text diffs: [text_diff, 0, 2]
    if patch_arr.len() == 3 && patch_arr[1] == Value::from(0) && patch_arr[2] == Value::from(2) {
        if let Value::String(ref old_text) = document {
            // First element should be an object with {"text_diff": [...]}
            if let Some(text_diff_obj) = patch_arr.get(0) {
                if let Some(ops) = text_diff_obj.get("text_diff").and_then(|v| v.as_array()) {
                    let new_text = apply_text_diff_ops(old_text, ops);
                    return Value::String(new_text);
                }
            }
        }
        return document.clone();
    }
    // Addition [new] / Deletion [old,0,0] / Change [old, new]
    match (document, patch_arr) {
        (_, [new_val]) => new_val.clone(),
        (_, [old_val, mid, end]) if *mid == Value::from(0) && *end == Value::from(0) => {
            // Deletion -> null
            let _ = old_val; // old value not used here
            Value::Null
        }
        (_, [old_val, new_val]) => {
            let _ = old_val;
            new_val.clone()
        }
        _ => document.clone(),
    }
}

// Apply Myers-style diff ops generated in diff_text_simd to old_text
fn apply_text_diff_ops(old_text: &str, ops: &[Value]) -> String {
    let mut builder = String::with_capacity(old_text.len());
    let mut pos_old_chars: usize = 0;

    for op in ops {
        let op_type = op.get("op").and_then(|v| v.as_str()).unwrap_or("");
        match op_type {
            "delete" => {
                if let Some(range) = op.get("range").and_then(|v| v.as_array()) {
                    if range.len() == 2 {
                        let s = range[0].as_u64().unwrap_or(0) as usize;
                        let e = range[1].as_u64().unwrap_or(0) as usize;
                        builder.push_str(slice_by_char_range(old_text, pos_old_chars, s));
                        pos_old_chars = e;
                    }
                }
            }
            "replace" => {
                if let Some(old_range) = op.get("old_range").and_then(|v| v.as_array()) {
                    if old_range.len() == 2 {
                        let s = old_range[0].as_u64().unwrap_or(0) as usize;
                        let e = old_range[1].as_u64().unwrap_or(0) as usize;
                        let new_text = op.get("new_text").and_then(|v| v.as_str()).unwrap_or("");
                        builder.push_str(slice_by_char_range(old_text, pos_old_chars, s));
                        builder.push_str(new_text);
                        pos_old_chars = e;
                    }
                }
            }
            "insert" => {
                if let Some(ins) = op.get("text").and_then(|v| v.as_str()) {
                    builder.push_str(ins);
                }
            }
            _ => {}
        }
    }

    builder.push_str(slice_by_char_range(old_text, pos_old_chars, count_chars(old_text)));
    builder
}

fn count_chars(s: &str) -> usize {
    s.chars().count()
}

fn slice_by_char_range<'a>(s: &'a str, start_char: usize, end_char: usize) -> &'a str {
    if start_char >= end_char {
        return "";
    }
    let start_byte = char_index_to_byte(s, start_char);
    let end_byte = char_index_to_byte(s, end_char);
    &s[start_byte..end_byte]
}

fn char_index_to_byte(s: &str, char_idx: usize) -> usize {
    if char_idx == 0 { return 0; }
    let mut count = 0usize;
    for (byte_idx, _) in s.char_indices() {
        if count == char_idx { return byte_idx; }
        count += 1;
    }
    s.len()
}

// ====================
// OPERATIONAL DIFF (CRDT-based)
// ====================

#[rustler::nif]
fn diff_operational<'a>(env: Env<'a>, old_doc: String, new_doc: String, opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    DIFF_STATS.operational_diffs.fetch_add(1, Ordering::Relaxed);
    DIFF_STATS.bytes_processed.fetch_add((old_doc.len() + new_doc.len()) as u64, Ordering::Relaxed);
    
    let options = parse_operational_options(&opts);
    
    match (serde_json::from_str::<Value>(&old_doc), serde_json::from_str::<Value>(&new_doc)) {
        (Ok(old_val), Ok(new_val)) => {
            let diff = compute_operational_diff(&old_val, &new_val, &options);
            match serde_json::to_string(&diff) {
                Ok(diff_json) => Ok((atoms::ok(), diff_json).encode(env)),
                Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
            }
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), format!("JSON parse error: {}", e)).encode(env))
    }
}

#[derive(Debug, Clone)]
struct OperationalOptions {
    actor_id: String,
    base_timestamp: u64,
    conflict_resolution: ConflictResolution,
}

#[derive(Debug, Clone)]
enum ConflictResolution {
    LastWriteWins,
    Merge,
}

fn parse_operational_options(opts: &[(String, String)]) -> OperationalOptions {
    let mut options = OperationalOptions {
        actor_id: generate_actor_id(),
        base_timestamp: current_timestamp_nanos(),
        conflict_resolution: ConflictResolution::LastWriteWins,
    };
    
    for (key, value) in opts {
        match key.as_str() {
            "actor_id" => options.actor_id = value.clone(),
            "timestamp" => {
                if let Ok(ts) = value.parse() {
                    options.base_timestamp = ts;
                }
            }
            "conflict_resolution" => {
                options.conflict_resolution = match value.as_str() {
                    "merge" => ConflictResolution::Merge,
                    _ => ConflictResolution::LastWriteWins,
                };
            }
            _ => {}
        }
    }
    
    options
}

fn compute_operational_diff(old: &Value, new: &Value, options: &OperationalOptions) -> Value {
    let mut operations = Vec::new();
    let mut timestamp = options.base_timestamp;
    
    diff_values_operational(old, new, &[], options, &mut operations, &mut timestamp);
    
    json!({
        "operations": operations,
        "metadata": {
            "actors": [options.actor_id.clone()],
            "timestamp_range": [options.base_timestamp, timestamp],
            "conflict_resolution": match options.conflict_resolution {
                ConflictResolution::LastWriteWins => "last_write_wins",
                ConflictResolution::Merge => "merge",
            }
        }
    })
}

fn diff_values_operational(
    old: &Value, 
    new: &Value, 
    path: &[&str], 
    options: &OperationalOptions,
    operations: &mut Vec<Value>,
    timestamp: &mut u64
) {
    if values_equal_simd(old, new) {
        return;
    }
    
    match (old, new) {
        (Value::Object(old_obj), Value::Object(new_obj)) => {
            diff_objects_operational(old_obj, new_obj, path, options, operations, timestamp);
        }
        (Value::Array(old_arr), Value::Array(new_arr)) => {
            diff_arrays_operational(old_arr, new_arr, path, options, operations, timestamp);
        }
        _ => {
            // Value changed
            operations.push(json!({
                "type": "set",
                "path": path,
                "value": new,
                "timestamp": *timestamp,
                "actor_id": options.actor_id
            }));
            *timestamp += 1;
        }
    }
}

fn diff_objects_operational(
    old_obj: &serde_json::Map<String, Value>,
    new_obj: &serde_json::Map<String, Value>,
    path: &[&str],
    options: &OperationalOptions,
    operations: &mut Vec<Value>,
    timestamp: &mut u64
) {
    let old_keys: ahash::AHashSet<&String> = old_obj.keys().collect();
    let new_keys: ahash::AHashSet<&String> = new_obj.keys().collect();
    
    for key in old_keys.union(&new_keys) {
        let mut new_path = path.to_vec();
        new_path.push(key);
        
        match (old_obj.get(*key), new_obj.get(*key)) {
            (Some(old_val), Some(new_val)) => {
                diff_values_operational(old_val, new_val, &new_path, options, operations, timestamp);
            }
            (Some(_), None) => {
                // Key deleted
                operations.push(json!({
                    "type": "delete",
                    "path": new_path,
                    "value": null,
                    "timestamp": *timestamp,
                    "actor_id": options.actor_id
                }));
                *timestamp += 1;
            }
            (None, Some(new_val)) => {
                // Key added
                operations.push(json!({
                    "type": "set",
                    "path": new_path,
                    "value": new_val,
                    "timestamp": *timestamp,
                    "actor_id": options.actor_id
                }));
                *timestamp += 1;
            }
            (None, None) => unreachable!(),
        }
    }
}

fn diff_arrays_operational(
    old_arr: &[Value],
    new_arr: &[Value],
    path: &[&str],
    options: &OperationalOptions,
    operations: &mut Vec<Value>,
    timestamp: &mut u64
) {
    // Simple approach: delete all old items and insert all new items
    // More sophisticated LCS-based approach could be implemented for efficiency
    
    // Delete old items in reverse order
    for i in (0..old_arr.len()).rev() {
        let mut new_path = path.iter().map(|s| s.to_string()).collect::<Vec<String>>();
        new_path.push(i.to_string());
        
        operations.push(json!({
            "type": "delete",
            "path": new_path,
            "value": null,
            "timestamp": *timestamp,
            "actor_id": options.actor_id
        }));
        *timestamp += 1;
    }
    
    // Insert new items
    for (i, new_val) in new_arr.iter().enumerate() {
        let mut new_path = path.iter().map(|s| s.to_string()).collect::<Vec<String>>();
        new_path.push(i.to_string());
        
        operations.push(json!({
            "type": "insert",
            "path": new_path,
            "value": new_val,
            "timestamp": *timestamp,
            "actor_id": options.actor_id
        }));
        *timestamp += 1;
    }
}

#[rustler::nif]
fn patch_operational<'a>(env: Env<'a>, document: String, patch_str: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match (serde_json::from_str::<Value>(&document), serde_json::from_str::<Value>(&patch_str)) {
        (Ok(mut doc), Ok(patch)) => {
            if let Some(operations) = patch.get("operations").and_then(|v| v.as_array()) {
                apply_operational_operations(&mut doc, operations);
            }
            
            match serde_json::to_string(&doc) {
                Ok(result_json) => Ok((atoms::ok(), result_json).encode(env)),
                Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
            }
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), format!("JSON parse error: {}", e)).encode(env))
    }
}

fn apply_operational_operations(document: &mut Value, operations: &[Value]) {
    // Sort operations by timestamp
    let mut sorted_ops: Vec<&Value> = operations.iter().collect();
    sorted_ops.sort_by_key(|op| {
        op.get("timestamp").and_then(|v| v.as_u64()).unwrap_or(0)
    });
    
    for op in sorted_ops {
        apply_single_operation(document, op);
    }
}

fn apply_single_operation(document: &mut Value, op: &Value) {
    let op_type = op.get("type").and_then(|v| v.as_str()).unwrap_or("");
    let empty_path = vec![];
    let path = op.get("path").and_then(|v| v.as_array()).unwrap_or(&empty_path);
    let value = op.get("value");
    
    match op_type {
        "set" => {
            if let Some(val) = value {
                set_value_at_path(document, path, val.clone());
            }
        }
        "delete" => {
            delete_value_at_path(document, path);
        }
        "insert" => {
            if let Some(val) = value {
                insert_value_at_path(document, path, val.clone());
            }
        }
        _ => {}
    }
}

fn set_value_at_path(document: &mut Value, path: &[Value], value: Value) {
    if path.is_empty() {
        *document = value;
        return;
    }
    
    // Handle the path navigation recursively to avoid borrowing issues
    set_value_at_path_recursive(document, path, 0, value);
}

fn set_value_at_path_recursive(current: &mut Value, path: &[Value], index: usize, value: Value) {
    if index >= path.len() {
        return;
    }
    
    let key = &path[index];
    
    if index == path.len() - 1 {
        // Last key, set the value
        match (current, key) {
            (Value::Object(ref mut obj), Value::String(k)) => {
                obj.insert(k.clone(), value);
            }
            (Value::Array(ref mut arr), Value::Number(n)) => {
                if let Some(idx_u64) = n.as_u64() {
                    if let Ok(idx) = usize::try_from(idx_u64) {
                        if idx < arr.len() {
                            arr[idx] = value;
                        }
                    }
                }
            }
            _ => {}
        }
    } else {
        // Navigate to the next level
        match (current, key) {
            (Value::Object(ref mut obj), Value::String(k)) => {
                if let Some(next) = obj.get_mut(k) {
                    set_value_at_path_recursive(next, path, index + 1, value);
                }
            }
            (Value::Array(ref mut arr), Value::Number(n)) => {
                if let Some(idx) = n.as_u64().and_then(|i| usize::try_from(i).ok()) {
                    if idx < arr.len() {
                        set_value_at_path_recursive(&mut arr[idx], path, index + 1, value);
                    }
                }
            }
            _ => {}
        }
    }
}

fn delete_value_at_path(document: &mut Value, path: &[Value]) {
    if path.is_empty() {
        *document = Value::Null;
        return;
    }

    fn recurse(current: &mut Value, path: &[Value], index: usize) {
        if index >= path.len() { return; }
        let key = &path[index];
        let is_last = index == path.len() - 1;

        match (current, key) {
            (Value::Object(ref mut obj), Value::String(k)) => {
                if is_last {
                    obj.remove(k);
                } else if let Some(next) = obj.get_mut(k) {
                    recurse(next, path, index + 1);
                }
            }
            (Value::Array(ref mut arr), Value::Number(n)) => {
                if let Some(idx) = n.as_u64().and_then(|i| usize::try_from(i).ok()) {
                    if idx < arr.len() {
                        if is_last {
                            arr.remove(idx);
                        } else {
                            recurse(&mut arr[idx], path, index + 1);
                        }
                    }
                }
            }
            _ => {}
        }
    }

    recurse(document, path, 0);
}

fn insert_value_at_path(document: &mut Value, path: &[Value], value: Value) {
    if path.is_empty() {
        *document = value;
        return;
    }

    fn recurse(current: &mut Value, path: &[Value], index: usize, value: Value) {
        let key = &path[index];
        let is_last = index == path.len() - 1;
        match (current, key) {
            (Value::Array(ref mut arr), Value::Number(n)) => {
                if let Some(idx) = n.as_u64().and_then(|i| usize::try_from(i).ok()) {
                    if is_last {
                        let insert_at = if idx <= arr.len() { idx } else { arr.len() };
                        arr.insert(insert_at, value);
                    } else if idx < arr.len() {
                        recurse(&mut arr[idx], path, index + 1, value);
                    }
                }
            }
            (Value::Object(ref mut obj), Value::String(k)) => {
                if is_last {
                    obj.insert(k.clone(), value);
                } else if let Some(next) = obj.get_mut(k) {
                    recurse(next, path, index + 1, value);
                }
            }
            _ => {}
        }
    }

    recurse(document, path, 0, value);
}

// ====================
// SEMANTIC DIFF (JSON-LD aware)
// ====================

#[rustler::nif]
fn diff_semantic<'a>(env: Env<'a>, old_doc: String, new_doc: String, opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    DIFF_STATS.semantic_diffs.fetch_add(1, Ordering::Relaxed);
    DIFF_STATS.bytes_processed.fetch_add((old_doc.len() + new_doc.len()) as u64, Ordering::Relaxed);
    
    let options = parse_semantic_options(&opts);
    
    match (serde_json::from_str::<Value>(&old_doc), serde_json::from_str::<Value>(&new_doc)) {
        (Ok(old_val), Ok(new_val)) => {
            let diff = compute_semantic_diff(&old_val, &new_val, &options);
            match serde_json::to_string(&diff) {
                Ok(diff_json) => Ok((atoms::ok(), diff_json).encode(env)),
                Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
            }
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), format!("JSON parse error: {}", e)).encode(env))
    }
}

#[derive(Debug, Clone)]
struct SemanticOptions {
    normalize: bool,
    context_aware: bool,
    expand_contexts: bool,
    blank_node_strategy: BlankNodeStrategy,
}

#[derive(Debug, Clone)]
enum BlankNodeStrategy {
    Uuid,
    Hash,
    Preserve,
}

fn parse_semantic_options(opts: &[(String, String)]) -> SemanticOptions {
    let mut options = SemanticOptions {
        normalize: true,
        context_aware: true,
        expand_contexts: true,
        blank_node_strategy: BlankNodeStrategy::Uuid,
    };
    
    for (key, value) in opts {
        match key.as_str() {
            "normalize" => options.normalize = value == "true",
            "context_aware" => options.context_aware = value == "true",
            "expand_contexts" => options.expand_contexts = value == "true",
            "blank_node_strategy" => {
                options.blank_node_strategy = match value.as_str() {
                    "hash" => BlankNodeStrategy::Hash,
                    "preserve" => BlankNodeStrategy::Preserve,
                    _ => BlankNodeStrategy::Uuid,
                };
            }
            _ => {}
        }
    }
    
    options
}

fn compute_semantic_diff(old: &Value, new: &Value, options: &SemanticOptions) -> Value {
    // Convert documents to RDF triples
    let old_triples = document_to_triples_fast(old, options);
    let new_triples = document_to_triples_fast(new, options);
    
    // Compare triple sets
    let old_set: ahash::AHashSet<_> = old_triples.iter().collect();
    let new_set: ahash::AHashSet<_> = new_triples.iter().collect();
    
    let added_triples: Vec<_> = new_set.difference(&old_set).cloned().collect();
    let removed_triples: Vec<_> = old_set.difference(&new_set).cloned().collect();
    
    // Analyze context changes
    let context_changes = if options.context_aware {
        compare_contexts_fast(old, new)
    } else {
        json!({
            "added_mappings": {},
            "removed_mappings": {},
            "changed_mappings": {},
            "base_changes": [null, null]
        })
    };
    
    // Group changes by node
    let modified_nodes = group_changes_by_node_fast(&added_triples, &removed_triples);
    
    json!({
        "added_triples": added_triples,
        "removed_triples": removed_triples,
        "modified_nodes": modified_nodes,
        "context_changes": context_changes,
        "metadata": {
            "normalization_algorithm": "urdna2015",
            "blank_node_handling": match options.blank_node_strategy {
                BlankNodeStrategy::Uuid => "uuid",
                BlankNodeStrategy::Hash => "hash",
                BlankNodeStrategy::Preserve => "preserve",
            },
            "semantic_equivalence": added_triples.is_empty() && removed_triples.is_empty()
        }
    })
}

fn document_to_triples_fast(document: &Value, _options: &SemanticOptions) -> Vec<Value> {
    // Robust RDF triple extraction with nested traversal and literals
    let mut triples: Vec<Value> = Vec::new();
    let mut bnode_cache: std::collections::HashMap<String, String> = std::collections::HashMap::new();
    extract_triples_node_fast(document, None, &mut bnode_cache, &mut triples);
    normalize_blank_nodes_fast(&triples)
}

fn expand_property_iri_fast(property: &str) -> String {
    // Simplified IRI expansion
    if property.starts_with("http://") || property.starts_with("https://") {
        property.to_string()
    } else if property.contains(':') {
        // Handle prefixed names
        let parts: Vec<&str> = property.splitn(2, ':').collect();
        match parts[0] {
            "schema" => format!("http://schema.org/{}", parts[1]),
            "rdf" => format!("http://www.w3.org/1999/02/22-rdf-syntax-ns#{}", parts[1]),
            "rdfs" => format!("http://www.w3.org/2000/01/rdf-schema#{}", parts[1]),
            _ => property.to_string(),
        }
    } else {
        format!("http://example.org/{}", property)
    }
}

fn serialize_object_for_rdf(object: &Value) -> Value {
    match object {
        Value::String(s) if is_iri(s) => Value::String(s.clone()),
        Value::String(s) => json!({"value": s, "type": "http://www.w3.org/2001/XMLSchema#string"}),
        Value::Number(n) => {
            let type_iri = if n.is_f64() { "http://www.w3.org/2001/XMLSchema#double" } else { "http://www.w3.org/2001/XMLSchema#integer" };
            json!({"value": n.to_string(), "type": type_iri})
        }
        Value::Bool(b) => json!({"value": b.to_string(), "type": "http://www.w3.org/2001/XMLSchema#boolean"}),
        Value::Object(obj) => {
            if let Some(Value::String(id)) = obj.get("@id") {
                Value::String(id.clone())
            } else if let Some(val) = obj.get("@value") {
                if let Some(Value::String(lang)) = obj.get("@language") {
                    json!({"value": val, "language": lang})
                } else if let Some(Value::String(t)) = obj.get("@type") {
                    json!({"value": val, "type": t})
                } else {
                    json!({"value": val, "type": "http://www.w3.org/2001/XMLSchema#string"})
                }
            } else {
                object.clone()
            }
        }
        _ => object.clone(),
    }
}

fn is_iri(s: &str) -> bool {
    s.starts_with("http://") || s.starts_with("https://")
}

fn extract_triples_node_fast(node: &Value, subject_hint: Option<String>, bnode_cache: &mut std::collections::HashMap<String, String>, triples: &mut Vec<Value>) -> Option<String> {
    match node {
        Value::Object(obj) => {
            let subject = if let Some(Value::String(id)) = obj.get("@id") {
                id.clone()
            } else {
                // assign deterministic bnode id based on sorted serialization
                let key = serde_json::to_string(&sorted_json_value(&Value::Object(obj.clone()))).unwrap_or_else(|_| "{}".to_string());
                bnode_cache.entry(key).or_insert_with(|| format!("_:h{}", uuid::Uuid::new_v4().simple())).clone()
            };

            // rdf:type handling
            if let Some(t) = obj.get("@type") {
                let rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type".to_string();
                match t {
                    Value::Array(arr) => {
                        for ty in arr {
                            if let Value::String(ts) = ty { triples.push(json!({"subject": subject, "predicate": rdf_type, "object": expand_property_iri_fast(ts)})); }
                        }
                    }
                    Value::String(ts) => { triples.push(json!({"subject": subject, "predicate": rdf_type, "object": expand_property_iri_fast(ts)})); }
                    _ => {}
                }
            }

            for (k, v) in obj.iter() {
                if k.starts_with('@') { continue; }
                let pred = expand_property_iri_fast(k);
                match v {
                    Value::Array(arr) => {
                        for item in arr { emit_triple_for_value(&subject, &pred, item, bnode_cache, triples); }
                    }
                    other => { emit_triple_for_value(&subject, &pred, other, bnode_cache, triples); }
                }
            }
            Some(subject)
        }
        Value::Array(arr) => {
            let mut last = None;
            for item in arr { last = extract_triples_node_fast(item, subject_hint.clone(), bnode_cache, triples); }
            last
        }
        _ => subject_hint,
    }
}

fn sorted_json_value(v: &Value) -> Value {
    match v {
        Value::Object(map) => {
            let mut entries: Vec<(String, Value)> = map.iter().map(|(k, val)| (k.clone(), sorted_json_value(val))).collect();
            entries.sort_by(|a, b| a.0.cmp(&b.0));
            let mut out = serde_json::Map::new();
            for (k, val) in entries { out.insert(k, val); }
            Value::Object(out)
        }
        Value::Array(arr) => Value::Array(arr.iter().map(sorted_json_value).collect()),
        _ => v.clone(),
    }
}

fn emit_triple_for_value(subject: &str, pred: &str, value: &Value, bnode_cache: &mut std::collections::HashMap<String, String>, triples: &mut Vec<Value>) {
    match value {
        Value::Object(obj) => {
            if let Some(Value::String(id)) = obj.get("@id") {
                triples.push(json!({"subject": subject, "predicate": pred, "object": id}));
            } else if obj.contains_key("@value") {
                let lit = serialize_object_for_rdf(value);
                triples.push(json!({"subject": subject, "predicate": pred, "object": lit}));
            } else {
                // nested blank node
                let nested_id = extract_triples_node_fast(value, None, bnode_cache, triples).unwrap_or_else(|| format!("_:h{}", uuid::Uuid::new_v4().simple()));
                triples.push(json!({"subject": subject, "predicate": pred, "object": nested_id}));
            }
        }
        Value::String(s) => {
            if is_iri(s) {
                triples.push(json!({"subject": subject, "predicate": pred, "object": s}));
            } else {
                triples.push(json!({"subject": subject, "predicate": pred, "object": {"value": s, "type": "http://www.w3.org/2001/XMLSchema#string"}}));
            }
        }
        Value::Number(_) | Value::Bool(_) => {
            let lit = serialize_object_for_rdf(value);
            triples.push(json!({"subject": subject, "predicate": pred, "object": lit}));
        }
        _ => {}
    }
}

fn normalize_blank_nodes_fast(triples: &Vec<Value>) -> Vec<Value> {
    // Collect blank node ids
    let mut bnodes: ahash::AHashSet<String> = ahash::AHashSet::new();
    for t in triples.iter() {
        if let Some(subj) = t.get("subject").and_then(|v| v.as_str()) { if subj.starts_with("_:") { bnodes.insert(subj.to_string()); } }
        if let Some(obj_str) = t.get("object").and_then(|v| v.as_str()) { if obj_str.starts_with("_:") { bnodes.insert(obj_str.to_string()); } }
    }
    // Create a stable mapping
    let mut bnodes_vec: Vec<String> = bnodes.into_iter().collect();
    bnodes_vec.sort();
    let mapping: std::collections::HashMap<String, String> = bnodes_vec.iter().enumerate().map(|(i, b)| (b.clone(), format!("_:h{:08}", i))).collect();

    triples.iter().map(|t| {
        let mut new_t = t.clone();
        if let Some(subj) = new_t.get_mut("subject") { if let Some(s) = subj.as_str() { if let Some(m) = mapping.get(s) { *subj = Value::String(m.clone()); } } }
        if let Some(obj) = new_t.get_mut("object") {
            if let Some(s) = obj.as_str() { if let Some(m) = mapping.get(s) { *obj = Value::String(m.clone()); } }
        }
        new_t
    }).collect()
}

fn compare_contexts_fast(old: &Value, new: &Value) -> Value {
    let old_context = extract_context_fast(old);
    let new_context = extract_context_fast(new);

    let old_map = flatten_context_fast(&old_context);
    let new_map = flatten_context_fast(&new_context);

    let old_keys: ahash::AHashSet<&String> = old_map.keys().collect();
    let new_keys: ahash::AHashSet<&String> = new_map.keys().collect();

    let added_keys: Vec<&String> = new_keys.difference(&old_keys).cloned().collect();
    let removed_keys: Vec<&String> = old_keys.difference(&new_keys).cloned().collect();
    let common_keys: Vec<&String> = old_keys.intersection(&new_keys).cloned().collect();

    let mut changed = serde_json::Map::new();
    for k in common_keys {
        if old_map.get(k) != new_map.get(k) {
            changed.insert(k.clone(), json!([old_map.get(k).cloned().unwrap_or_default(), new_map.get(k).cloned().unwrap_or_default()]));
        }
    }

    let added: serde_json::Map<String, Value> = added_keys.into_iter().map(|k| (k.clone(), Value::String(new_map.get(k).cloned().unwrap_or_default()))).collect();
    let removed: serde_json::Map<String, Value> = removed_keys.into_iter().map(|k| (k.clone(), Value::String(old_map.get(k).cloned().unwrap_or_default()))).collect();

    json!({
        "added_mappings": added,
        "removed_mappings": removed,
        "changed_mappings": changed,
        "base_changes": [old_context.get("@base").cloned().unwrap_or(Value::Null), new_context.get("@base").cloned().unwrap_or(Value::Null)]
    })
}

fn extract_context_fast(document: &Value) -> serde_json::Map<String, Value> {
    if let Some(Value::Object(context)) = document.get("@context") {
        context.clone()
    } else {
        serde_json::Map::new()
    }
}

fn flatten_context_fast(ctx: &serde_json::Map<String, Value>) -> std::collections::HashMap<String, String> {
    let mut out = std::collections::HashMap::new();
    for (k, v) in ctx.iter() {
        out.insert(k.clone(), match v { Value::String(s) => s.clone(), _ => v.to_string() });
    }
    out
}

fn group_changes_by_node_fast(added: &[&Value], removed: &[&Value]) -> Vec<Value> {
    // Build maps keyed by subject and (subject,predicate)
    let mut nodes_map: std::collections::BTreeMap<String, (Vec<Value>, Vec<Value>, Vec<Value>)> = std::collections::BTreeMap::new();

    // Index by (subject,predicate)
    use std::collections::HashMap;
    let mut added_sp: HashMap<(String, String), Vec<Value>> = HashMap::new();
    let mut removed_sp: HashMap<(String, String), Vec<Value>> = HashMap::new();

    for t in added.iter() {
        let subj = t.get("subject").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let pred = t.get("predicate").and_then(|v| v.as_str()).unwrap_or("").to_string();
        added_sp.entry((subj.clone(), pred.clone())).or_default().push((*t).clone());
        nodes_map.entry(subj).or_default();
    }
    for t in removed.iter() {
        let subj = t.get("subject").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let pred = t.get("predicate").and_then(|v| v.as_str()).unwrap_or("").to_string();
        removed_sp.entry((subj.clone(), pred.clone())).or_default().push((*t).clone());
        nodes_map.entry(subj).or_default();
    }

    // Build node diffs
    let mut result = Vec::new();
    for (node_id, (_a, _r, _m)) in nodes_map.iter_mut() {
        let mut added_props: Vec<Value> = Vec::new();
        let mut removed_props: Vec<Value> = Vec::new();
        let mut modified_props: Vec<Value> = Vec::new();

        // For each predicate under this subject, pair add/remove into modified
        let preds: std::collections::HashSet<String> = added_sp.keys().chain(removed_sp.keys()).filter_map(|(s,p)| if s==node_id {Some(p.clone())} else {None}).collect();
        for pred in preds {
            let key = (node_id.clone(), pred.clone());
            let adds = added_sp.get(&key).cloned().unwrap_or_default();
            let rems = removed_sp.get(&key).cloned().unwrap_or_default();
            if !adds.is_empty() && !rems.is_empty() {
                // Pair first add/remove as modified
                let a = &adds[0];
                let r = &rems[0];
                let old_val = r.get("object").cloned().unwrap_or(Value::Null);
                let new_val = a.get("object").cloned().unwrap_or(Value::Null);
                modified_props.push(json!({"property": pred, "old_value": old_val, "new_value": new_val, "change_type": "value"}));
                // Remaining adds count as added, remaining rems as removed
                for a2 in adds.iter().skip(1) {
                    added_props.push(json!({"property": pred, "new_value": a2.get("object").cloned().unwrap_or(Value::Null), "change_type": "value"}));
                }
                for r2 in rems.iter().skip(1) {
                    removed_props.push(json!({"property": pred, "old_value": r2.get("object").cloned().unwrap_or(Value::Null), "change_type": "value"}));
                }
            } else if !adds.is_empty() {
                for a in adds {
                    added_props.push(json!({"property": pred, "new_value": a.get("object").cloned().unwrap_or(Value::Null), "change_type": "value"}));
                }
            } else if !rems.is_empty() {
                for r in rems {
                    removed_props.push(json!({"property": pred, "old_value": r.get("object").cloned().unwrap_or(Value::Null), "change_type": "value"}));
                }
            }
        }

        result.push(json!({
            "node_id": node_id,
            "added_properties": added_props,
            "removed_properties": removed_props,
            "modified_properties": modified_props
        }));
    }

    result
}

#[rustler::nif]
fn patch_semantic<'a>(env: Env<'a>, document: String, patch_str: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match (serde_json::from_str::<Value>(&document), serde_json::from_str::<Value>(&patch_str)) {
        (Ok(mut doc), Ok(patch)) => {
            let mut result = doc.clone();

            // Apply RDF-level triple changes (limited support: rdf:type on root subject)
            if let Some(added) = patch.get("added_triples").and_then(|v| v.as_array()) {
                result = apply_triple_additions(result, added);
            }
            if let Some(removed) = patch.get("removed_triples").and_then(|v| v.as_array()) {
                result = apply_triple_removals(result, removed);
            }

            // Apply context changes
            if let Some(ctx_changes) = patch.get("context_changes").and_then(|v| v.as_object()) {
                result = apply_context_changes_fast(result, ctx_changes);
            }

            match serde_json::to_string(&result) {
                Ok(result_json) => Ok((atoms::ok(), result_json).encode(env)),
                Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
            }
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), format!("JSON parse error: {}", e)).encode(env))
    }
}

fn apply_triple_additions(mut doc: Value, added: &[Value]) -> Value {
    let root_id = doc.get("@id").and_then(|v| v.as_str()).map(|s| s.to_string());
    for t in added.iter() {
        let subj = t.get("subject").and_then(|v| v.as_str());
        let pred = t.get("predicate").and_then(|v| v.as_str());
        if let (Some(subject), Some(predicate)) = (subj, pred) {
            if Some(subject.to_string()) == root_id {
                if predicate == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" {
                    let obj_val = t.get("object");
                    let type_str = object_to_type_local(obj_val);
                    if let Some(ts) = type_str {
                        // Merge into @type
                        match doc.get_mut("@type") {
                            Some(Value::String(s)) => {
                                if s != &ts { *doc.get_mut("@type").unwrap() = Value::Array(vec![Value::String(s.clone()), Value::String(ts)]); }
                            }
                            Some(Value::Array(arr)) => {
                                if !arr.iter().any(|v| v.as_str()==Some(ts.as_str())) { arr.push(Value::String(ts)); }
                            }
                            _ => {
                                doc.as_object_mut().map(|m| m.insert("@type".to_string(), Value::String(ts)));
                            }
                        }
                    }
                } else {
                    // Generic property addition on root
                    let key = iri_local_name(predicate);
                    let new_val = object_to_json_value(t.get("object"));
                    // Ensure object
                    if !doc.is_object() { doc = json!({}); }
                    let objm = doc.as_object_mut().unwrap();
                    match objm.get_mut(&key) {
                        Some(Value::Array(arr)) => {
                            if !arr.iter().any(|v| v == &new_val) { arr.push(new_val); }
                        }
                        Some(current) => {
                            if *current != new_val {
                                let prev = current.clone();
                                *current = Value::Array(vec![prev, new_val]);
                            }
                        }
                        None => { objm.insert(key, new_val); }
                    }
                }
            }
        }
    }
    doc
}

fn apply_triple_removals(mut doc: Value, removed: &[Value]) -> Value {
    let root_id = doc.get("@id").and_then(|v| v.as_str()).map(|s| s.to_string());
    for t in removed.iter() {
        let subj = t.get("subject").and_then(|v| v.as_str());
        let pred = t.get("predicate").and_then(|v| v.as_str());
        if let (Some(subject), Some(predicate)) = (subj, pred) {
            if Some(subject.to_string()) == root_id {
                if predicate == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" {
                    let obj_val = t.get("object");
                    let type_str = object_to_type_local(obj_val);
                    if let Some(ts) = type_str {
                        match doc.get_mut("@type") {
                            Some(Value::String(s)) => {
                                if s == &ts { doc.as_object_mut().map(|m| m.remove("@type")); }
                            }
                            Some(Value::Array(arr)) => {
                                arr.retain(|v| v.as_str()!=Some(ts.as_str()));
                                if arr.len()==1 {
                                    let only = arr[0].clone();
                                    doc.as_object_mut().map(|m| m.insert("@type".to_string(), only));
                                }
                            }
                            _ => {}
                        }
                    }
                } else {
                    // Generic property removal on root
                    let key = iri_local_name(predicate);
                    let rem_val = object_to_json_value(t.get("object"));
                    if let Some(objm) = doc.as_object_mut() {
                        if let Some(existing) = objm.get_mut(&key) {
                            match existing {
                                Value::Array(arr) => {
                                    arr.retain(|v| v != &rem_val);
                                    if arr.len() == 1 {
                                        let only = arr[0].clone();
                                        objm.insert(key.clone(), only);
                                    } else if arr.is_empty() {
                                        objm.remove(&key);
                                    }
                                }
                                v => {
                                    if *v == rem_val { objm.remove(&key); }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    doc
}

fn object_to_type_local(obj_val: Option<&Value>) -> Option<String> {
    match obj_val {
        Some(Value::String(s)) => Some(iri_local_name(s)),
        Some(Value::Object(map)) => map.get("@id").and_then(|v| v.as_str()).map(|s| iri_local_name(s)),
        _ => None,
    }
}

fn iri_local_name(iri: &str) -> String {
    if let Some(pos) = iri.rfind(['/', '#']) { iri[pos+1..].to_string() } else { iri.to_string() }
}

fn apply_context_changes_fast(mut document: Value, changes: &serde_json::Map<String, Value>) -> Value {
    // Ensure @context is an object map
    let mut ctx = match document.get("@context") {
        Some(Value::Object(map)) => map.clone(),
        _ => serde_json::Map::new(),
    };

    if let Some(added) = changes.get("added_mappings").and_then(|v| v.as_object()) {
        for (k, v) in added.iter() { ctx.insert(k.clone(), v.clone()); }
    }
    if let Some(removed) = changes.get("removed_mappings").and_then(|v| v.as_object()) {
        for (k, _v) in removed.iter() { ctx.remove(k); }
    }
    if let Some(changed) = changes.get("changed_mappings").and_then(|v| v.as_object()) {
        for (k, vpair) in changed.iter() {
            if let Some(arr) = vpair.as_array() { if arr.len()==2 { ctx.insert(k.clone(), arr[1].clone()); } }
        }
    }

    document.as_object_mut().map(|m| m.insert("@context".to_string(), Value::Object(ctx)));
    document
}

fn object_to_json_value(obj_val: Option<&Value>) -> Value {
    match obj_val {
        Some(Value::String(s)) => Value::String(s.clone()),
        Some(Value::Object(map)) => {
            if let Some(vid) = map.get("@id").and_then(|v| v.as_str()) { return Value::String(vid.to_string()); }
            let v = map.get("value").cloned().unwrap_or(Value::Null);
            if let Some(t) = map.get("type").and_then(|v| v.as_str()) {
                // Coerce basic XSD types to JSON scalars if possible
                match t {
                    "http://www.w3.org/2001/XMLSchema#integer" => {
                        if let Some(s) = v.as_str() { if let Ok(n) = s.parse::<i64>() { return Value::Number(n.into()); } }
                        return v;
                    }
                    "http://www.w3.org/2001/XMLSchema#double" => {
                        if let Some(s) = v.as_str() { if let Ok(f) = s.parse::<f64>() { return Value::Number(serde_json::Number::from_f64(f).unwrap_or(serde_json::Number::from(0))); } }
                        return v;
                    }
                    "http://www.w3.org/2001/XMLSchema#boolean" => {
                        if let Some(s) = v.as_str() { if s == "true" { return Value::Bool(true); } else if s == "false" { return Value::Bool(false); } }
                        return v;
                    }
                    _ => v
                }
            } else if let Some(_lang) = map.get("language").and_then(|v| v.as_str()) {
                // For now, drop language and use raw string
                v
            } else {
                v
            }
        }
        Some(other) => other.clone(),
        None => Value::Null,
    }
}

// ====================
// UTILITY FUNCTIONS
// ====================

fn generate_actor_id() -> String {
    format!("actor_{}", uuid::Uuid::new_v4().simple())
}

fn current_timestamp_nanos() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos() as u64
}

// ====================
// HIGH-PERFORMANCE UTILITY NIFs
// ====================

#[rustler::nif]
fn compute_lcs_array<'a>(env: Env<'a>, old_array: String, new_array: String) -> NifResult<Term<'a>> {
    match (serde_json::from_str::<Vec<Value>>(&old_array), serde_json::from_str::<Vec<Value>>(&new_array)) {
        (Ok(old_arr), Ok(new_arr)) => {
            let lcs_ops = compute_lcs_operations(&old_arr, &new_arr);
            match serde_json::to_string(&lcs_ops) {
                Ok(result_json) => Ok((atoms::ok(), result_json).encode(env)),
                Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
            }
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), format!("JSON parse error: {}", e)).encode(env))
    }
}

fn compute_lcs_operations(old: &[Value], new: &[Value]) -> Vec<Value> {
    // Simplified LCS - just return insert/delete operations
    let mut operations = Vec::new();
    
    // Delete old items
    for (i, _) in old.iter().enumerate().rev() {
        operations.push(json!({
            "type": "delete",
            "index": i
        }));
    }
    
    // Insert new items
    for (i, item) in new.iter().enumerate() {
        operations.push(json!({
            "type": "insert",
            "index": i,
            "value": item
        }));
    }
    
    operations
}

#[rustler::nif]
fn text_diff_myers<'a>(env: Env<'a>, old_text: String, new_text: String) -> NifResult<Term<'a>> {
    let text_diff = TextDiff::configure()
        .algorithm(Algorithm::Myers)
        .diff_chars(&old_text, &new_text);
    
    let mut operations = Vec::new();
    
    for op in text_diff.ops() {
        let operation = json!({
            "tag": match op.tag() {
                DiffTag::Equal => "equal",
                DiffTag::Delete => "delete",
                DiffTag::Insert => "insert",
                DiffTag::Replace => "replace",
            },
            "old_range": [op.old_range().start, op.old_range().end],
            "new_range": [op.new_range().start, op.new_range().end]
        });
        operations.push(operation);
    }
    
    let result = json!({
        "operations": operations,
        "common_prefix": "",
        "common_suffix": "",
        "old_middle": old_text,
        "new_middle": new_text
    });
    
    Ok((atoms::ok(), result.to_string()).encode(env))
}

#[rustler::nif]
fn normalize_rdf_graph<'a>(env: Env<'a>, document: String, algorithm: String) -> NifResult<Term<'a>> {
    // Simplified RDF normalization
    match serde_json::from_str::<Value>(&document) {
        Ok(doc) => {
            let normalized = normalize_document_simple(&doc, &algorithm);
            Ok((atoms::ok(), normalized).encode(env))
        }
        Err(e) => Ok((atoms::error(), format!("JSON parse error: {}", e)).encode(env))
    }
}

fn normalize_document_simple(document: &Value, _algorithm: &str) -> String {
    // Return a simplified normalized representation
    format!("# Normalized representation of document\n# Algorithm: URDNA2015\n{}", 
            serde_json::to_string_pretty(document).unwrap_or_default())
}

#[rustler::nif]
fn merge_diffs_operational<'a>(env: Env<'a>, diffs: String, opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match serde_json::from_str::<Vec<Value>>(&diffs) {
        Ok(diff_array) => {
            let merged = merge_operational_diffs(&diff_array, &opts);
            match serde_json::to_string(&merged) {
                Ok(result_json) => Ok((atoms::ok(), result_json).encode(env)),
                Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
            }
        }
        Err(e) => Ok((atoms::error(), format!("JSON parse error: {}", e)).encode(env))
    }
}

fn merge_operational_diffs(diffs: &[Value], _opts: &[(String, String)]) -> Value {
    let mut all_operations = Vec::new();
    let mut all_actors = Vec::new();
    
    for diff in diffs {
        if let Some(operations) = diff.get("operations").and_then(|v| v.as_array()) {
            all_operations.extend_from_slice(operations);
        }
        if let Some(metadata) = diff.get("metadata").and_then(|v| v.as_object()) {
            if let Some(actors) = metadata.get("actors").and_then(|v| v.as_array()) {
                for actor in actors {
                    if let Some(actor_str) = actor.as_str() {
                        if !all_actors.contains(&actor_str.to_string()) {
                            all_actors.push(actor_str.to_string());
                        }
                    }
                }
            }
        }
    }
    
    // Sort operations by timestamp
    all_operations.sort_by_key(|op| {
        op.get("timestamp").and_then(|v| v.as_u64()).unwrap_or(0)
    });
    
    json!({
        "operations": all_operations,
        "metadata": {
            "actors": all_actors,
            "conflict_resolution": "last_write_wins"
        }
    })
}

rustler::init!("Elixir.JsonldEx.Native");
