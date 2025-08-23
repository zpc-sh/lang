use rustler::{Error, NifResult, NifStruct, NifUnitEnum};
use std::path::{Path, PathBuf};
use std::fs;
use rayon::prelude::*;
use ignore::WalkBuilder;
use grep::regex::RegexMatcher;
use grep::searcher::Searcher;

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

fn scan_recursive(
    path: &Path, 
    depth: usize, 
    max_depth: usize, 
    include_hidden: bool,
    stats: Arc<std::sync::Mutex<ScanStats>>
) -> Result<FileNode, std::io::Error> {
    let metadata = fs::metadata(path)?;
    let name = path.file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    
    let modified_time = metadata.modified()
        .unwrap_or_else(|_| std::time::SystemTime::UNIX_EPOCH)
        .duration_since(std::time::SystemTime::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    
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
            
            analyze_file_content(path)
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
            node_type: if metadata.is_file() { 
                FileType::File 
            } else { 
                FileType::Symlink 
            },
            size: metadata.len(),
            extension: path.extension()
                .map(|e| e.to_string_lossy().to_string()),
            modified_time,
            children: None,
            metadata: file_metadata,
        })
    }
}

fn analyze_file_content(path: &Path) -> FileMetadata {
    // Quick file analysis
    if let Ok(file) = fs::File::open(path) {
        if let Ok(mmap) = unsafe { Mmap::map(&file) } {
            let content = &mmap[..std::cmp::min(mmap.len(), 8192)]; // First 8KB
            
            let is_binary = content.contains(&0u8);
            if is_binary {
                return FileMetadata {
                    lines: None,
                    language: detect_language_from_extension(path),
                    is_binary: true,
                    encoding: Some("binary".to_string()),
                };
            }
            
            // Count lines in sample
            let lines = mmap.iter().filter(|&&b| b == b'\n').count() as u64;
            
            return FileMetadata {
                lines: Some(lines),
                language: detect_language_from_extension(path),
                is_binary: false,
                encoding: Some("utf-8".to_string()),
            };
        }
    }
    
    FileMetadata {
        lines: None,
        language: detect_language_from_extension(path),
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
    let matcher = if case_sensitive {
        RegexMatcher::new(&pattern)
    } else {
        RegexMatcher::new_line_matcher(&pattern)
    };
    
    let matcher = matcher
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
        
        let line_text = String::from_utf8_lossy(mat.bytes()).to_string();
        let line_number = mat.line_number().unwrap_or(0);
        
        // Extract context lines
        let (context_before, context_after) = self.extract_context(line_number);
        
        let result = SearchResult {
            path: self.path.to_string_lossy().to_string(),
            line_number,
            line_text: line_text.trim_end().to_string(),
            match_start: 0, // Would need more work to get exact position
            match_end: line_text.len(),
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
    max_results: usize
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
        .max_depth(Some(15))
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
    match fs::read_to_string(&path) {
        Ok(content) => {
            let lines: Vec<String> = content
                .lines()
                .take(max_lines)
                .map(|s| s.to_string())
                .collect();
            Ok(lines)
        },
        Err(_) => Err(Error::Term(Box::new("read_error"))),
    }
}

rustler::init!(
    "Elixir.Lang.Native.FSScanner",
    [
        scan_directory,
        search_content,
        search_code_patterns,
        get_file_preview
    ]
);