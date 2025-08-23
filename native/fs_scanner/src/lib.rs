use rustler::{Error, NifResult, NifStruct, NifUnitEnum};
use std::path::{Path, PathBuf};
use std::fs;
use rayon::prelude::*;
use ignore::WalkBuilder;
use grep::regex::RegexMatcher;
use grep::searcher::Searcher;
use grep::matcher::Matcher;
use regex::RegexSet;

use dashmap::DashMap;
use std::sync::Arc;
use memmap2::Mmap;
use std::sync::atomic::{AtomicUsize, Ordering};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        file,
        directory,
        symlink,
        timeout,
        not_found
    }
}

#[derive(Debug, NifStruct)]
#[module = "Lang.Native.FSScanner.FileNode"]
struct FileNode {
    path: String,
    name: String,
    node_type: FileType,
    size: u64,
    extension: Option<String>,
    modified_time: u64,
    children: Option<Vec<FileNode>>,
    metadata: FileMetadata,
}

#[derive(Debug, NifStruct)]
#[module = "Lang.Native.FSScanner.FileMetadata"]
struct FileMetadata {
    lines: Option<u64>,
    language: Option<String>,
    is_binary: bool,
    encoding: Option<String>,
}

#[derive(Debug, NifUnitEnum)]
enum FileType {
    File,
    Directory,
    Symlink,
}

#[derive(Debug, Clone, NifStruct)]
#[module = "Lang.Native.FSScanner.SearchResult"]
struct SearchResult {
    path: String,
    line_number: u64,
    line_text: String,
    match_start: usize,
    match_end: usize,
    context_before: Vec<String>,
    context_after: Vec<String>,
}

#[derive(Debug, Clone, NifStruct)]
#[module = "Lang.Native.FSScanner.CodeMatch"]
struct CodeMatch {
    path: String,
    start_line: u64,
    end_line: u64,
    start_column: u64,
    end_column: u64,
    matched_text: String,
    capture_name: String,
    node_type: String,
}

#[derive(Debug, NifStruct)]
#[module = "Lang.Native.FSScanner.ScanStats"]
struct ScanStats {
    total_files: u64,
    total_directories: u64,
    total_size: u64,
    scan_duration_ms: u64,
    files_by_extension: std::collections::HashMap<String, u64>,
}

/// High-performance directory scanning with parallel processing
#[rustler::nif(schedule = "DirtyCpu")]
fn scan_directory(path: String, max_depth: usize, include_hidden: bool) -> NifResult<(FileNode, ScanStats)> {
    let start_time = std::time::Instant::now();
    let path = Path::new(&path);
    
    if !path.exists() {
        return Err(Error::Term(Box::new("path_not_found")));
    }
    
    let stats = Arc::new(std::sync::Mutex::new(ScanStats {
        total_files: 0,
        total_directories: 0,
        total_size: 0,
        scan_duration_ms: 0,
        files_by_extension: std::collections::HashMap::new(),
    }));
    
    match scan_recursive(path, 0, max_depth, include_hidden, stats.clone()) {
        Ok(node) => {
            let mut stats_guard = stats.lock().unwrap();
            stats_guard.scan_duration_ms = start_time.elapsed().as_millis() as u64;
            let final_stats = ScanStats {
                total_files: stats_guard.total_files,
                total_directories: stats_guard.total_directories,
                total_size: stats_guard.total_size,
                scan_duration_ms: stats_guard.scan_duration_ms,
                files_by_extension: stats_guard.files_by_extension.clone(),
            };
            Ok((node, final_stats))
        },
        Err(e) => Err(Error::Term(Box::new(format!("scan_error: {}", e)))),
    }
}

/// Directory scanning with include/exclude globs and max file size
#[rustler::nif(schedule = "DirtyCpu")]
fn scan_directory_filtered(
    path: String,
    max_depth: usize,
    include_hidden: bool,
    include_globs: Vec<String>,
    exclude_globs: Vec<String>,
    max_file_size_bytes: u64,
) -> NifResult<(FileNode, ScanStats)> {
    let start_time = std::time::Instant::now();
    let root = std::path::PathBuf::from(&path);
    let include_set = build_regexset(&include_globs);
    let exclude_set = build_regexset(&exclude_globs);

    let path = root.as_path();
    if !path.exists() {
        return Err(Error::Term(Box::new("path_not_found")));
    }

    let stats = Arc::new(std::sync::Mutex::new(ScanStats {
        total_files: 0,
        total_directories: 0,
        total_size: 0,
        scan_duration_ms: 0,
        files_by_extension: std::collections::HashMap::new(),
    }));

    match scan_recursive_filtered(
        path,
        0,
        max_depth,
        include_hidden,
        stats.clone(),
        &root,
        include_set.as_ref(),
        exclude_set.as_ref(),
        max_file_size_bytes,
    ) {
        Ok(node) => {
            let mut stats_guard = stats.lock().unwrap();
            stats_guard.scan_duration_ms = start_time.elapsed().as_millis() as u64;
            let final_stats = ScanStats {
                total_files: stats_guard.total_files,
                total_directories: stats_guard.total_directories,
                total_size: stats_guard.total_size,
                scan_duration_ms: stats_guard.scan_duration_ms,
                files_by_extension: stats_guard.files_by_extension.clone(),
            };
            Ok((node, final_stats))
        }
        Err(e) => Err(Error::Term(Box::new(format!("scan_error: {}", e)))),
    }
}

fn scan_recursive(
    path: &Path,
    depth: usize,
    max_depth: usize,
    include_hidden: bool,
    stats: Arc<std::sync::Mutex<ScanStats>>,
) -> Result<FileNode, std::io::Error> {
    // Never follow symlinks to avoid cycles
    let symlink_meta = fs::symlink_metadata(path)?;
    let file_type = symlink_meta.file_type();
    // Use metadata for size/mtime where appropriate (it follows symlinks)
    let metadata = if file_type.is_symlink() {
        symlink_meta
    } else {
        // Fall back to regular metadata for non-symlinks
        fs::metadata(path)?
    };
    let name = path.file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    
    let modified_time = metadata.modified()
        .unwrap_or_else(|_| std::time::SystemTime::UNIX_EPOCH)
        .duration_since(std::time::SystemTime::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    
    if file_type.is_symlink() {
        // Represent symlink without traversing
        return Ok(FileNode {
            path: path.to_string_lossy().to_string(),
            name,
            node_type: FileType::Symlink,
            size: 0,
            extension: path.extension().map(|e| e.to_string_lossy().to_string()),
            modified_time,
            children: None,
            metadata: FileMetadata { lines: None, language: detect_language_from_path(path), is_binary: false, encoding: None },
        });
    }

    if metadata.is_dir() && depth < max_depth {
        // Update directory count
        {
            let mut stats_guard = stats.lock().unwrap();
            stats_guard.total_directories += 1;
        }
        
        let mut entries: Vec<_> = fs::read_dir(path)?
            .filter_map(|e| e.ok())
            .filter(|entry| {
                if !include_hidden {
                    let file_name = entry.file_name();
                    let name = file_name.to_string_lossy();
                    !name.starts_with('.')
                } else {
                    true
                }
            })
            .collect();
            
        // Sort for consistent ordering
        entries.sort_by_key(|e| e.path());
        
        // Use parallel processing for large directories
        let children: Vec<FileNode> = if entries.len() > 50 {
            entries
                .into_par_iter()
                .filter_map(|entry| {
                    let path = entry.path();
                    if should_ignore(&path) {
                        None
                    } else {
                        scan_recursive(&path, depth + 1, max_depth, include_hidden, stats.clone()).ok()
                    }
                })
                .collect()
        } else {
            entries
                .into_iter()
                .filter_map(|entry| {
                    let path = entry.path();
                    if should_ignore(&path) {
                        None
                    } else {
                        scan_recursive(&path, depth + 1, max_depth, include_hidden, stats.clone()).ok()
                    }
                })
                .collect()
        };
        
        Ok(FileNode {
            path: path.to_string_lossy().to_string(),
            name,
            node_type: FileType::Directory,
            size: 0,
            extension: None,
            modified_time,
            children: Some(children),
            metadata: FileMetadata {
                lines: None,
                language: None,
                is_binary: false,
                encoding: None,
            },
        })
    } else if metadata.is_dir() {
        // Max depth reached: still represent as a directory without children
        let mut stats_guard = stats.lock().unwrap();
        stats_guard.total_directories += 1;
        drop(stats_guard);

        Ok(FileNode {
            path: path.to_string_lossy().to_string(),
            name: name.clone(),
            node_type: FileType::Directory,
            size: 0,
            extension: None,
            modified_time,
            children: None,
            metadata: FileMetadata { lines: None, language: None, is_binary: false, encoding: None },
        })
    } else {
        let file_metadata = if metadata.is_file() {
            // Update file stats
            let size = metadata.len();
            let extension = path.extension().map(|e| e.to_string_lossy().to_string());
            
            {
                let mut stats_guard = stats.lock().unwrap();
                stats_guard.total_files += 1;
                stats_guard.total_size += size;
                
                if let Some(ref ext) = extension {
                    *stats_guard.files_by_extension.entry(ext.clone()).or_insert(0) += 1;
                }
            }
            
            analyze_file_content(path, size)
        } else {
            FileMetadata {
                lines: None,
                language: None,
                is_binary: false,
                encoding: None,
            }
        };
        
        Ok(FileNode {
            path: path.to_string_lossy().to_string(),
            name: name.clone(),
            node_type: if metadata.is_file() { FileType::File } else { FileType::Symlink },
            size: metadata.len(),
            extension: path.extension()
                .map(|e| e.to_string_lossy().to_string()),
            modified_time,
            children: None,
            metadata: file_metadata,
        })
    }
}

#[inline]
fn matches_globs(
    root: &Path,
    path: &Path,
    include: Option<&RegexSet>,
    exclude: Option<&RegexSet>,
    is_dir: bool,
) -> bool {
    let rel = path.strip_prefix(root).unwrap_or(path);
    let s = rel.to_string_lossy();
    if let Some(ex) = exclude {
        if ex.is_match(&s) {
            return false;
        }
    }
    if let Some(inc) = include {
        // For directories, allow traversal even if they don't match include patterns
        if is_dir {
            return true;
        }
        return inc.is_match(&s);
    }
    true
}

fn build_regexset(patterns: &Vec<String>) -> Option<RegexSet> {
    if patterns.is_empty() {
        return None;
    }
    let mut regexes = Vec::with_capacity(patterns.len());
    for p in patterns {
        if let Some(rx) = glob_to_regex(p) {
            regexes.push(rx);
        }
    }
    if regexes.is_empty() { None } else { RegexSet::new(regexes).ok() }
}

fn glob_to_regex(glob: &str) -> Option<String> {
    let mut out = String::from("^");
    let mut chars = glob.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '.' | '+' | '(' | ')' | '|' | '^' | '$' | '{' | '}' | '[' | ']' | '\\' => {
                out.push('\\');
                out.push(c);
            }
            '*' => {
                if matches!(chars.peek(), Some('*')) {
                    let _ = chars.next();
                    out.push_str(".*");
                } else {
                    out.push_str("[^/]*");
                }
            }
            '?' => out.push('.'),
            '/' => out.push('/'),
            _ => out.push(c),
        }
    }
    out.push('$');
    Some(out)
}

fn scan_recursive_filtered(
    path: &Path,
    depth: usize,
    max_depth: usize,
    include_hidden: bool,
    stats: Arc<std::sync::Mutex<ScanStats>>,
    root: &Path,
    include: Option<&RegexSet>,
    exclude: Option<&RegexSet>,
    max_file_size_bytes: u64,
) -> Result<FileNode, std::io::Error> {
    let symlink_meta = fs::symlink_metadata(path)?;
    let file_type = symlink_meta.file_type();
    let metadata = if file_type.is_symlink() { symlink_meta } else { fs::metadata(path)? };

    let name = path.file_name().unwrap_or_default().to_string_lossy().to_string();
    let modified_time = metadata
        .modified()
        .unwrap_or_else(|_| std::time::SystemTime::UNIX_EPOCH)
        .duration_since(std::time::SystemTime::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    if file_type.is_symlink() {
        return Ok(FileNode {
            path: path.to_string_lossy().to_string(),
            name,
            node_type: FileType::Symlink,
            size: 0,
            extension: path.extension().map(|e| e.to_string_lossy().to_string()),
            modified_time,
            children: None,
            metadata: FileMetadata { lines: None, language: detect_language_from_path(path), is_binary: false, encoding: None },
        });
    }

    if metadata.is_dir() && depth < max_depth {
        {
            let mut stats_guard = stats.lock().unwrap();
            stats_guard.total_directories += 1;
        }

        let mut entries: Vec<_> = fs::read_dir(path)?
            .filter_map(|e| e.ok())
            .filter(|entry| {
                if !include_hidden {
                    let file_name = entry.file_name();
                    let name = file_name.to_string_lossy();
                    if name.starts_with('.') { return false; }
                }
                let p = entry.path();
                // Do not block directories on include globs
                let is_dir = entry.file_type().map(|ft| ft.is_dir()).unwrap_or(false);
                matches_globs(root, &p, include, exclude, is_dir)
            })
            .collect();
        entries.sort_by_key(|e| e.path());

        let children: Vec<FileNode> = if entries.len() > 50 {
            entries
                .into_par_iter()
                .filter_map(|entry| {
                    let p = entry.path();
                    if should_ignore(&p) { None } else {
                        scan_recursive_filtered(&p, depth + 1, max_depth, include_hidden, stats.clone(), root, include, exclude, max_file_size_bytes).ok()
                    }
                })
                .collect()
        } else {
            entries
                .into_iter()
                .filter_map(|entry| {
                    let p = entry.path();
                    if should_ignore(&p) { None } else {
                        scan_recursive_filtered(&p, depth + 1, max_depth, include_hidden, stats.clone(), root, include, exclude, max_file_size_bytes).ok()
                    }
                })
                .collect()
        };

        return Ok(FileNode {
            path: path.to_string_lossy().to_string(),
            name,
            node_type: FileType::Directory,
            size: 0,
            extension: None,
            modified_time,
            children: Some(children),
            metadata: FileMetadata { lines: None, language: None, is_binary: false, encoding: None },
        });
    } else if metadata.is_dir() {
        let mut stats_guard = stats.lock().unwrap();
        stats_guard.total_directories += 1;
        drop(stats_guard);
        return Ok(FileNode {
            path: path.to_string_lossy().to_string(),
            name: name.clone(),
            node_type: FileType::Directory,
            size: 0,
            extension: None,
            modified_time,
            children: None,
            metadata: FileMetadata { lines: None, language: None, is_binary: false, encoding: None },
        });
    }

    if !matches_globs(root, path, include, exclude, false) {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "filtered"));
    }
    if max_file_size_bytes > 0 && metadata.len() > max_file_size_bytes {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "filtered"));
    }

    let size = metadata.len();
    let extension = path.extension().map(|e| e.to_string_lossy().to_string());
    {
        let mut stats_guard = stats.lock().unwrap();
        stats_guard.total_files += 1;
        stats_guard.total_size += size;
        if let Some(ref ext) = extension {
            *stats_guard.files_by_extension.entry(ext.clone()).or_insert(0) += 1;
        }
    }
    let file_metadata = analyze_file_content(path, size);

    Ok(FileNode {
        path: path.to_string_lossy().to_string(),
        name: name.clone(),
        node_type: FileType::File,
        size,
        extension,
        modified_time,
        children: None,
        metadata: file_metadata,
    })
}

fn analyze_file_content(path: &Path, size: u64) -> FileMetadata {
    // Quick file analysis
    // Avoid mapping extremely large files
    const MAX_ANALYZE_BYTES: u64 = 8 * 1024 * 1024; // 8MB safety cap
    if size > MAX_ANALYZE_BYTES {
        return FileMetadata {
            lines: None,
            language: detect_language_from_path(path),
            is_binary: false,
            encoding: None,
        };
    }

    if let Ok(file) = fs::File::open(path) {
        if let Ok(mmap) = unsafe { Mmap::map(&file) } {
            let content = &mmap[..std::cmp::min(mmap.len(), 8192)]; // First 8KB
            
            let is_binary = content.contains(&0u8);
            if is_binary {
                return FileMetadata {
                    lines: None,
                    language: detect_language_from_path(path),
                    is_binary: true,
                    encoding: Some("binary".to_string()),
                };
            }
            
            // Count lines in sample
            let lines = mmap.iter().filter(|&&b| b == b'\n').count() as u64;
            
            return FileMetadata {
                lines: Some(lines),
                language: detect_language_from_path(path),
                is_binary: false,
                encoding: Some("utf-8".to_string()),
            };
        }
    }
    
    FileMetadata {
        lines: None,
        language: detect_language_from_path(path),
        is_binary: false,
        encoding: None,
    }
}

fn detect_language_from_extension(path: &Path) -> Option<String> {
    let ext = path.extension()?.to_str()?;
    
    let language = match ext.to_lowercase().as_str() {
        "rs" => "rust",
        "ex" | "exs" => "elixir",
        "js" | "jsx" => "javascript",
        "ts" | "tsx" => "typescript",
        "py" => "python",
        "go" => "go",
        "rb" => "ruby",
        "php" => "php",
        "java" => "java",
        "c" => "c",
        "cpp" | "cc" | "cxx" => "cpp",
        "h" | "hpp" => "c_header",
        "cs" => "csharp",
        "swift" => "swift",
        "kt" => "kotlin",
        "scala" => "scala",
        "clj" | "cljs" => "clojure",
        "hs" => "haskell",
        "ml" => "ocaml",
        "fs" => "fsharp",
        "elm" => "elm",
        "dart" => "dart",
        "lua" => "lua",
        "r" => "r",
        "jl" => "julia",
        "nim" => "nim",
        "zig" => "zig",
        "v" => "vlang",
        "html" | "htm" => "html",
        "css" => "css",
        "scss" | "sass" => "scss",
        "json" => "json",
        "xml" => "xml",
        "yaml" | "yml" => "yaml",
        "toml" => "toml",
        "md" => "markdown",
        "sql" => "sql",
        "sh" | "bash" => "bash",
        "ps1" => "powershell",
        "dockerfile" => "dockerfile",
        "makefile" => "makefile",
        _ => return None,
    };
    
    Some(language.to_string())
}

fn detect_language_from_path(path: &Path) -> Option<String> {
    // Try extension first
    if let Some(lang) = detect_language_from_extension(path) {
        return Some(lang);
    }
    // Fallback to common filenames
    if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
        match name {
            "Dockerfile" => return Some("dockerfile".to_string()),
            "Makefile" => return Some("makefile".to_string()),
            _ => {}
        }
    }
    None
}

fn should_ignore(path: &Path) -> bool {
    let ignore_dirs = [
        ".git", "node_modules", "_build", "deps", "target", 
        ".elixir_ls", "__pycache__", ".next", "dist", "build",
        ".cache", ".tmp", "tmp", "temp", ".DS_Store", "Thumbs.db"
    ];
    
    let ignore_files = [
        ".DS_Store", "Thumbs.db", "desktop.ini", ".gitkeep"
    ];
    
    if let Some(name) = path.file_name() {
        let name_str = name.to_string_lossy();
        ignore_dirs.iter().any(|&dir| name_str == dir) ||
        ignore_files.iter().any(|&file| name_str == file)
    } else {
        false
    }
}

/// Ripgrep-powered content search with context
#[rustler::nif(schedule = "DirtyCpu")]
fn search_content(
    root_path: String, 
    pattern: String, 
    max_results: usize,
    context_lines: usize,
    case_sensitive: bool
) -> NifResult<Vec<SearchResult>> {
    // Build regex with proper case sensitivity
    let mut builder = grep::regex::RegexMatcherBuilder::new();
    builder.case_insensitive(!case_sensitive);
    let matcher = builder
        .build(&pattern)
        .map_err(|e| Error::Term(Box::new(format!("regex_error: {}", e))))?;

    // Separate regex just to compute match offsets on a matched line
    let mut re_builder = regex::bytes::RegexBuilder::new(&pattern);
    re_builder.case_insensitive(!case_sensitive);
    re_builder.multi_line(true);
    let pos_re = re_builder
        .build()
        .map_err(|e| Error::Term(Box::new(format!("regex_error: {}", e))))?;
    
    let results = Arc::new(DashMap::new());
    let counter = Arc::new(AtomicUsize::new(0));
    
    WalkBuilder::new(&root_path)
        .hidden(false)
        .ignore(true)
        .git_ignore(true)
        .git_global(true)
        .git_exclude(true)
        .max_depth(Some(20))
        .threads(num_cpus::get())
        .build_parallel()
        .run(|| {
            let matcher = matcher.clone();
            let results = results.clone();
            let counter = counter.clone();
            let pos_re = pos_re.clone();
            
            Box::new(move |entry| {
                let entry = match entry {
                    Ok(e) => e,
                    Err(_) => return ignore::WalkState::Continue,
                };
                
                if counter.load(Ordering::Relaxed) >= max_results {
                    return ignore::WalkState::Quit;
                }
                
                if !entry.file_type().map_or(false, |ft| ft.is_file()) {
                    return ignore::WalkState::Continue;
                }
                
                let path = entry.path();
                // Default ignores for heavy/noisy directories
                if should_ignore(path) {
                    return ignore::WalkState::Continue;
                }
                
                // Skip binary files
                if is_likely_binary(path) {
                    return ignore::WalkState::Continue;
                }
                
                if let Ok(file) = fs::File::open(path) {
                    if let Ok(mmap) = unsafe { Mmap::map(&file) } {
                        let mut searcher = grep::searcher::SearcherBuilder::new()
                            .line_number(true)
                            .multi_line(true)
                            .build();
                            
                        let sink = SearchSink {
                            path: path.to_path_buf(),
                            results: results.clone(),
                            counter: counter.clone(),
                            max_results,
                            context_lines,
                            content: &mmap,
                            pos_re: pos_re.clone(),
                        };
                        
                        let _ = searcher.search_slice(&matcher, &mmap, sink);
                    }
                }
                
                ignore::WalkState::Continue
            })
        });
    
    let mut all_results: Vec<SearchResult> = results
        .iter()
        .flat_map(|entry| entry.value().clone())
        .collect();
        
    all_results.sort_by(|a, b| a.path.cmp(&b.path).then(a.line_number.cmp(&b.line_number)));
    all_results.truncate(max_results);
    
    Ok(all_results)
}

struct SearchSink<'a> {
    path: PathBuf,
    results: Arc<DashMap<PathBuf, Vec<SearchResult>>>,
    counter: Arc<AtomicUsize>,
    max_results: usize,
    context_lines: usize,
    content: &'a [u8],
    pos_re: regex::bytes::Regex,
}

impl<'a> grep::searcher::Sink for SearchSink<'a> {
    type Error = std::io::Error;
    
    fn matched(
        &mut self,
        _searcher: &Searcher,
        mat: &grep::searcher::SinkMatch<'_>,
    ) -> Result<bool, Self::Error> {
        if self.counter.load(Ordering::Relaxed) >= self.max_results {
            return Ok(false);
        }
        
        let line_bytes = mat.bytes();
        let line_text = String::from_utf8_lossy(line_bytes).to_string();
        let line_number = mat.line_number().unwrap_or(0);
        
        // Extract context lines
        let (context_before, context_after) = self.extract_context(line_number);

        // Compute match byte offsets within the line (first match)
        let (match_start, match_end) = if let Some(m) = self.pos_re.find(line_bytes) {
            (m.start(), m.end())
        } else {
            (0, line_text.len())
        };
        
        let result = SearchResult {
            path: self.path.to_string_lossy().to_string(),
            line_number,
            line_text: line_text.trim_end().to_string(),
            match_start,
            match_end,
            context_before,
            context_after,
        };
        
        self.results
            .entry(self.path.clone())
            .or_insert_with(Vec::new)
            .push(result);
            
        self.counter.fetch_add(1, Ordering::Relaxed);
        
        Ok(true)
    }
}

impl<'a> SearchSink<'a> {
    fn extract_context(&self, line_number: u64) -> (Vec<String>, Vec<String>) {
        if self.context_lines == 0 {
            return (Vec::new(), Vec::new());
        }
        
        let content_str = String::from_utf8_lossy(self.content);
        let lines: Vec<&str> = content_str.lines().collect();
        let current_line = (line_number as usize).saturating_sub(1);
        
        let start_context = current_line.saturating_sub(self.context_lines);
        let end_context = std::cmp::min(current_line + self.context_lines + 1, lines.len());
        
        let context_before = lines[start_context..current_line]
            .iter()
            .map(|s| s.to_string())
            .collect();
            
        let context_after = lines[(current_line + 1)..end_context]
            .iter()
            .map(|s| s.to_string())
            .collect();
        
        (context_before, context_after)
    }
}

fn is_likely_binary(path: &Path) -> bool {
    let binary_extensions = [
        "exe", "dll", "so", "dylib", "bin", "dat", "db", "sqlite",
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "ico",
        "mp3", "mp4", "avi", "mkv", "mov", "flv", "wav",
        "zip", "tar", "gz", "7z", "rar", "bz2", "xz",
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "ttf", "otf", "woff", "woff2", "eot",
    ];
    
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        binary_extensions.contains(&ext.to_lowercase().as_str())
    } else {
        false
    }
}

/// Tree-sitter powered semantic code search
#[rustler::nif(schedule = "DirtyCpu")]
fn search_code_patterns(
    root_path: String,
    language: String,
    pattern: String,
    max_results: usize,
    max_depth: usize
) -> NifResult<Vec<CodeMatch>> {
    use tree_sitter::{Parser, Query, QueryCursor};
    
    let lang = match language.as_str() {
        "rust" => tree_sitter_rust::language(),
        "javascript" => tree_sitter_javascript::language(),
        "typescript" => tree_sitter_typescript::language_typescript(),
        "python" => tree_sitter_python::language(),
        "go" => tree_sitter_go::language(),
        "java" => tree_sitter_java::language(),
        "c" => tree_sitter_c::language(),
        "cpp" => tree_sitter_cpp::language(),
        "json" => tree_sitter_json::language(),
        _ => return Err(Error::Term(Box::new(format!("unsupported_language: {}", language)))),
    };
    
    let _query = Query::new(lang, &pattern)
        .map_err(|e| Error::Term(Box::new(format!("query_error: {}", e))))?;
    
    let results = Arc::new(DashMap::new());
    let counter = Arc::new(AtomicUsize::new(0));
    
    let language_clone = language.clone();
    
    WalkBuilder::new(&root_path)
        .hidden(false)
        .ignore(true)
        .git_ignore(true)
        .git_global(true)
        .git_exclude(true)
        .max_depth(Some(max_depth))
        .build_parallel()
        .run(|| {
            let mut parser = Parser::new();
            parser.set_language(lang).unwrap();
            let query_str = pattern.clone();
            let results = results.clone();
            let counter = counter.clone();
            let language_str = language_clone.clone();
            
            Box::new(move |entry| {
                if counter.load(Ordering::Relaxed) >= max_results {
                    return ignore::WalkState::Quit;
                }
                
                let entry = match entry {
                    Ok(e) => e,
                    Err(_) => return ignore::WalkState::Continue,
                };
                
                let path = entry.path();
                if should_ignore(path) {
                    return ignore::WalkState::Continue;
                }
                if !is_target_language_file(path, &language_str) {
                    return ignore::WalkState::Continue;
                }
                
                if let Ok(content) = fs::read_to_string(path) {
                    if let Some(tree) = parser.parse(&content, None) {
                        let query = Query::new(lang, &query_str).unwrap();
                        let mut cursor = QueryCursor::new();
                        let matches = cursor.matches(&query, tree.root_node(), content.as_bytes());
                        
                        for mat in matches.take(10) { // Limit per file
                            if counter.load(Ordering::Relaxed) >= max_results {
                                break;
                            }
                            
                            for capture in mat.captures {
                                let node = capture.node;
                                let text = node.utf8_text(content.as_bytes()).unwrap_or("");
                                
                                let result = CodeMatch {
                                    path: path.to_string_lossy().to_string(),
                                    start_line: node.start_position().row as u64 + 1,
                                    end_line: node.end_position().row as u64 + 1,
                                    start_column: node.start_position().column as u64,
                                    end_column: node.end_position().column as u64,
                                    matched_text: text.to_string(),
                                    capture_name: query.capture_names()[capture.index as usize].to_string(),
                                    node_type: node.kind().to_string(),
                                };
                                
                                results.entry(path.to_path_buf())
                                    .or_insert_with(Vec::new)
                                    .push(result);
                                    
                                counter.fetch_add(1, Ordering::Relaxed);
                            }
                        }
                    }
                }
                
                ignore::WalkState::Continue
            })
        });
    
    let mut all_matches: Vec<CodeMatch> = results
        .iter()
        .flat_map(|entry| entry.value().clone())
        .collect();
    
    all_matches.sort_by(|a, b| {
        a.path.cmp(&b.path)
            .then(a.start_line.cmp(&b.start_line))
            .then(a.start_column.cmp(&b.start_column))
    });
    
    all_matches.truncate(max_results);
    Ok(all_matches)
}

fn is_target_language_file(path: &Path, language: &str) -> bool {
    let ext = path.extension()
        .and_then(|e| e.to_str())
        .unwrap_or("");
    
    match language {
        "rust" => ext == "rs",
        "javascript" => matches!(ext, "js" | "jsx"),
        "typescript" => matches!(ext, "ts" | "tsx"),
        "python" => ext == "py",
        "go" => ext == "go",
        "java" => ext == "java",
        "c" => ext == "c",
        "cpp" => matches!(ext, "cpp" | "cc" | "cxx"),
        "json" => ext == "json",
        _ => false,
    }
}

/// Fast file content preview
#[rustler::nif]
fn get_file_preview(path: String, max_lines: usize) -> NifResult<Vec<String>> {
    use std::io::{BufRead, BufReader};
    let path_ref = Path::new(&path);
    if is_likely_binary(path_ref) {
        return Err(Error::Term(Box::new("read_error")));
    }
    match fs::File::open(path_ref) {
        Ok(file) => {
            let reader = BufReader::new(file);
            let mut out = Vec::with_capacity(max_lines.min(1024));
            for (i, line) in reader.lines().enumerate() {
                if i >= max_lines { break; }
                match line {
                    Ok(s) => out.push(s),
                    Err(_) => break,
                }
            }
            Ok(out)
        }
        Err(_) => Err(Error::Term(Box::new("read_error"))),
    }
}

rustler::init!(
    "Elixir.Lang.Native.FSScanner",
    [
        scan_directory,
        scan_directory_filtered,
        search_content,
        search_code_patterns,
        get_file_preview
    ]
);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_language_by_extension() {
        assert_eq!(detect_language_from_extension(Path::new("foo.rs")).as_deref(), Some("rust"));
        assert_eq!(detect_language_from_extension(Path::new("bar.ex")).as_deref(), Some("elixir"));
        assert_eq!(detect_language_from_extension(Path::new("baz.unknown")).as_deref(), None);
    }

    #[test]
    fn detects_language_by_filename() {
        assert_eq!(detect_language_from_path(Path::new("/a/b/Dockerfile")).as_deref(), Some("dockerfile"));
        assert_eq!(detect_language_from_path(Path::new("/a/Makefile")).as_deref(), Some("makefile"));
    }
}
