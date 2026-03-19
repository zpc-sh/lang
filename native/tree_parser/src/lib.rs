// native/tree_parser/src/lib.rs - Tree-sitter AST Parsing Engine with Architectural Rule Checking
// Parses directory structures as ASTs and provides high-performance pattern matching

#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

use rustler::{Atom, Binary, Env, NifResult, Term, ResourceArc, OwnedBinary};
use std::sync::{Arc, RwLock, Mutex};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::ffi::CStr;
use tree_sitter::{Language, Parser, Query, QueryCursor, Tree, Node, Point, Range};
use dashmap::DashMap;
use rayon::prelude::*;
use serde::{Serialize, Deserialize};
use once_cell::sync::Lazy;
use ahash::AHashMap;
use parking_lot::RwLock as ParkingRwLock;
use globset::{Glob, GlobSet, GlobSetBuilder};
use walkdir::WalkDir;
use memmap2::Mmap;
use lz4_flex::{compress_prepend_size, decompress_size_prepended};
use crossbeam_channel::{Receiver, Sender, unbounded};
use regex::Regex;
use unicode_segmentation::UnicodeSegmentation;

// ============================================================================
// EXTERNAL LANGUAGE BINDINGS
// ============================================================================

extern "C" {
    fn tree_sitter_javascript() -> Language;
    fn tree_sitter_typescript() -> Language;
    fn tree_sitter_python() -> Language;
    fn tree_sitter_rust() -> Language;
    fn tree_sitter_go() -> Language;
    fn tree_sitter_elixir() -> Language;
    fn tree_sitter_markdown() -> Language;
    fn tree_sitter_json() -> Language;
    fn tree_sitter_yaml() -> Language;
    fn tree_sitter_html() -> Language;
    fn tree_sitter_css() -> Language;
    fn tree_sitter_sql() -> Language;
}

// ============================================================================
// RUSTLER MODULE INITIALIZATION
// ============================================================================

rustler::init!(
    "Elixir.Lang.Native.TreeParser",
    [
        create_parser,
        parse_source_code,
        parse_file_batch,
        query_ast_patterns,
        extract_symbols,
        analyze_complexity,
        check_architectural_rules,
        get_ast_statistics,
        compress_ast,
        decompress_ast,
        build_dependency_graph,
        validate_code_quality,
        find_code_smells,
        extract_documentation,
        analyze_semantic_structure
    ],
    load = on_load
);

fn on_load(env: Env, _info: Term) -> bool {
    rustler::resource!(ParserResource, env);
    rustler::resource!(AstResource, env);
    rustler::resource!(QueryResource, env);
    true
}

// Atoms for Elixir communication
rustler::atoms! {
    ok,
    error,
    invalid_syntax,
    unsupported_language,
    parse_error,
    query_error,
    rule_violation,
    high_complexity,
    code_smell_detected,
    missing_documentation
}

// Global caches and shared resources
static LANGUAGE_REGISTRY: Lazy<HashMap<String, Language>> = Lazy::new(|| {
    let mut registry = HashMap::new();
    
    unsafe {
        registry.insert("javascript".to_string(), tree_sitter_javascript());
        registry.insert("typescript".to_string(), tree_sitter_typescript());
        registry.insert("python".to_string(), tree_sitter_python());
        registry.insert("rust".to_string(), tree_sitter_rust());
        registry.insert("go".to_string(), tree_sitter_go());
        registry.insert("elixir".to_string(), tree_sitter_elixir());
        registry.insert("markdown".to_string(), tree_sitter_markdown());
        registry.insert("json".to_string(), tree_sitter_json());
        registry.insert("yaml".to_string(), tree_sitter_yaml());
        registry.insert("html".to_string(), tree_sitter_html());
        registry.insert("css".to_string(), tree_sitter_css());
        registry.insert("sql".to_string(), tree_sitter_sql());
    }
    
    registry
});

static AST_CACHE: Lazy<DashMap<String, Arc<AstCacheEntry>>> = Lazy::new(DashMap::new);
static QUERY_CACHE: Lazy<DashMap<String, Arc<Query>>> = Lazy::new(DashMap::new);
static PARSER_POOL: Lazy<ParserPool> = Lazy::new(ParserPool::new);

// ============================================================================
// DATA STRUCTURES - OPTIMIZED FOR AST PROCESSING
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AstNode {
    pub node_type: String,
    pub text: String,
    pub start_byte: u32,
    pub end_byte: u32,
    pub start_point: AstPoint,
    pub end_point: AstPoint,
    pub children: Vec<AstNode>,
    pub is_named: bool,
    pub field_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AstPoint {
    pub row: u32,
    pub column: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SymbolInfo {
    pub name: String,
    pub symbol_type: String,
    pub location: AstPoint,
    pub visibility: String,
    pub documentation: Option<String>,
    pub complexity: u32,
    pub dependencies: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComplexityMetrics {
    pub cyclomatic_complexity: u32,
    pub cognitive_complexity: u32,
    pub nesting_depth: u32,
    pub function_count: u32,
    pub class_count: u32,
    pub lines_of_code: u32,
    pub comment_ratio: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArchitecturalViolation {
    pub rule_id: String,
    pub severity: String,
    pub message: String,
    pub file_path: String,
    pub location: AstPoint,
    pub suggestion: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodeSmell {
    pub smell_type: String,
    pub severity: String,
    pub description: String,
    pub location: AstPoint,
    pub metrics: HashMap<String, f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DependencyNode {
    pub name: String,
    pub file_path: String,
    pub dependencies: Vec<String>,
    pub dependents: Vec<String>,
    pub weight: f64,
    pub centrality: f64,
}

pub struct ParserResource {
    pub language: String,
    pub parser: Arc<Mutex<Parser>>,
    pub queries: Arc<RwLock<HashMap<String, Query>>>,
}



pub struct AstResource {
    pub tree: Tree,
    pub source_code: String,
    pub language: String,
    pub file_path: Option<String>,
    pub metadata: AstMetadata,
}



pub struct QueryResource {
    pub query: Query,
    pub language: String,
    pub pattern: String,
}



#[derive(Debug, Clone)]
pub struct AstMetadata {
    pub parse_time_us: u64,
    pub node_count: u32,
    pub error_count: u32,
    pub warnings: Vec<String>,
}

#[derive(Debug)]
pub struct AstCacheEntry {
    pub ast: Tree,
    pub metadata: AstMetadata,
    pub created_at: std::time::Instant,
    pub access_count: std::sync::atomic::AtomicU64,
}

// ============================================================================
// PARSER POOL FOR EFFICIENT REUSE
// ============================================================================

pub struct ParserPool {
    parsers: DashMap<String, Vec<Parser>>,
    max_parsers_per_language: usize,
}

impl ParserPool {
    pub fn new() -> Self {
        Self {
            parsers: DashMap::new(),
            max_parsers_per_language: 10,
        }
    }

    pub fn get_parser(&self, language: &str) -> Option<Parser> {
        if let Some(mut parsers) = self.parsers.get_mut(language) {
            parsers.pop()
        } else if let Some(&lang) = LANGUAGE_REGISTRY.get(language) {
            let mut parser = Parser::new();
            parser.set_language(lang).ok()?;
            Some(parser)
        } else {
            None
        }
    }

    pub fn return_parser(&self, language: String, parser: Parser) {
        let mut parsers = self.parsers.entry(language).or_insert_with(Vec::new);
        if parsers.len() < self.max_parsers_per_language {
            parsers.push(parser);
        }
    }
}

// ============================================================================
// ARCHITECTURAL RULES ENGINE
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArchitecturalRule {
    pub id: String,
    pub name: String,
    pub description: String,
    pub query_pattern: String,
    pub severity: String,
    pub enabled: bool,
    pub file_patterns: Vec<String>,
}

pub struct ArchitecturalRulesEngine {
    rules: ParkingRwLock<Vec<ArchitecturalRule>>,
    compiled_queries: DashMap<String, Arc<Query>>,
    glob_matchers: ParkingRwLock<HashMap<String, GlobSet>>,
}

impl ArchitecturalRulesEngine {
    pub fn new() -> Self {
        Self {
            rules: ParkingRwLock::new(Vec::new()),
            compiled_queries: DashMap::new(),
            glob_matchers: ParkingRwLock::new(HashMap::new()),
        }
    }

    pub fn add_rules(&self, rules: Vec<ArchitecturalRule>) -> Result<(), String> {
        let mut rule_list = self.rules.write();
        
        for rule in rules {
            // Compile query for the rule
            if let Some(&language) = LANGUAGE_REGISTRY.get("javascript") {
                match Query::new(language, &rule.query_pattern) {
                    Ok(query) => {
                        self.compiled_queries.insert(rule.id.clone(), Arc::new(query));
                    }
                    Err(e) => {
                        return Err(format!("Failed to compile query for rule {}: {}", rule.id, e));
                    }
                }
            }
            
            rule_list.push(rule);
        }

        self.rebuild_glob_matchers(&rule_list)
    }

    pub fn check_violations(&self, ast: &Tree, source_code: &str, file_path: &str, language: &str) -> Vec<ArchitecturalViolation> {
        let rules = self.rules.read();
        let mut violations = Vec::new();

        for rule in rules.iter().filter(|r| r.enabled) {
            // Check if file matches rule patterns
            if !self.file_matches_patterns(&rule.file_patterns, file_path) {
                continue;
            }

            // Execute query against AST
            if let Some(query) = self.compiled_queries.get(&rule.id) {
                let mut cursor = QueryCursor::new();
                let matches = cursor.matches(&query, ast.root_node(), source_code.as_bytes());

                for mat in matches {
                    for capture in mat.captures {
                        let node = capture.node;
                        let location = AstPoint {
                            row: node.start_position().row as u32,
                            column: node.start_position().column as u32,
                        };

                        violations.push(ArchitecturalViolation {
                            rule_id: rule.id.clone(),
                            severity: rule.severity.clone(),
                            message: rule.description.clone(),
                            file_path: file_path.to_string(),
                            location,
                            suggestion: self.generate_suggestion(&rule.id, &node, source_code),
                        });
                    }
                }
            }
        }

        violations
    }

    fn file_matches_patterns(&self, patterns: &[String], file_path: &str) -> bool {
        if patterns.is_empty() {
            return true;
        }

        let glob_matchers = self.glob_matchers.read();
        patterns.iter().any(|pattern| {
            glob_matchers.get(pattern)
                .map(|glob_set| glob_set.is_match(file_path))
                .unwrap_or(false)
        })
    }

    fn rebuild_glob_matchers(&self, rules: &[ArchitecturalRule]) -> Result<(), String> {
        let mut matchers = HashMap::new();
        
        for rule in rules {
            for pattern in &rule.file_patterns {
                if !matchers.contains_key(pattern) {
                    let mut builder = GlobSetBuilder::new();
                    let glob = Glob::new(pattern)
                        .map_err(|e| format!("Invalid glob pattern '{}': {}", pattern, e))?;
                    builder.add(glob);
                    let glob_set = builder.build()
                        .map_err(|e| format!("Failed to build glob set: {}", e))?;
                    matchers.insert(pattern.clone(), glob_set);
                }
            }
        }

        *self.glob_matchers.write() = matchers;
        Ok(())
    }

    fn generate_suggestion(&self, rule_id: &str, node: &Node, source_code: &str) -> Option<String> {
        match rule_id {
            "no_long_functions" => Some("Consider breaking this function into smaller functions".to_string()),
            "no_deep_nesting" => Some("Consider extracting nested logic into separate functions".to_string()),
            "require_documentation" => Some("Add documentation comment for this function".to_string()),
            _ => None,
        }
    }
}

static RULES_ENGINE: Lazy<ArchitecturalRulesEngine> = Lazy::new(ArchitecturalRulesEngine::new);

// ============================================================================
// MAIN NIF FUNCTIONS
// ============================================================================

#[rustler::nif]
fn create_parser(language: String) -> NifResult<ResourceArc<ParserResource>> {
    if let Some(parser) = PARSER_POOL.get_parser(&language) {
        let resource = ParserResource {
            language: language.clone(),
            parser: Arc::new(Mutex::new(parser)),
            queries: Arc::new(RwLock::new(HashMap::new())),
        };
        
        Ok(ResourceArc::new(resource))
    } else {
        Err(rustler::Error::Term(Box::new("Unsupported language")))
    }
}

#[rustler::nif]
fn parse_source_code(
    language: String,
    source_code: String,
    file_path: Option<String>
) -> NifResult<ResourceArc<AstResource>> {
    let start_time = std::time::Instant::now();
    
    // Check cache first
    let cache_key = format!("{}:{}", language, xxhash_rust::xxh64::xxh64(source_code.as_bytes(), 0));
    if let Some(cached) = AST_CACHE.get(&cache_key) {
        cached.access_count.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        
        let resource = AstResource {
            tree: cached.ast.clone(),
            source_code,
            language,
            file_path,
            metadata: cached.metadata.clone(),
        };
        return Ok(ResourceArc::new(resource));
    }

    // Parse from scratch
    if let Some(mut parser) = PARSER_POOL.get_parser(&language) {
        match parser.parse(&source_code, None) {
            Some(tree) => {
                let parse_time_us = start_time.elapsed().as_micros() as u64;
                let node_count = count_nodes(&tree.root_node());
                let error_count = count_error_nodes(&tree.root_node());
                
                let metadata = AstMetadata {
                    parse_time_us,
                    node_count,
                    error_count,
                    warnings: Vec::new(),
                };

                // Cache the result
                let cache_entry = AstCacheEntry {
                    ast: tree.clone(),
                    metadata: metadata.clone(),
                    created_at: std::time::Instant::now(),
                    access_count: std::sync::atomic::AtomicU64::new(1),
                };
                AST_CACHE.insert(cache_key, Arc::new(cache_entry));

                // Return parser to pool
                PARSER_POOL.return_parser(language.clone(), parser);

                let resource = AstResource {
                    tree,
                    source_code,
                    language,
                    file_path,
                    metadata,
                };
                
                Ok(ResourceArc::new(resource))
            }
            None => {
                PARSER_POOL.return_parser(language, parser);
                Err(rustler::Error::Term(Box::new("Parse failed")))
            }
        }
    } else {
        Err(rustler::Error::Term(Box::new("Unsupported language")))
    }
}

fn internal_parse_source_code(
    language: String,
    source_code: String,
    file_path: Option<String>
) -> Result<ResourceArc<AstResource>, String> {
    let cache_key = format!("{}:{}", language, xxhash_rust::xxh64::xxh64(source_code.as_bytes(), 0));
    if let Some(cached) = AST_CACHE.get(&cache_key) {
        cached.access_count.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        
        let ast_resource = AstResource {
            tree: cached.ast.clone(),
            source_code: source_code.clone(),
            language: language.clone(),
            file_path: file_path.clone(),
            metadata: cached.metadata.clone(),
        };
        return Ok(ResourceArc::new(ast_resource));
    }

    if let Some(mut parser) = PARSER_POOL.get_parser(&language) {
        match parser.parse(&source_code, None) {
            Some(tree) => {
                let metadata = AstMetadata {
                    parse_time_us: 0,
                    node_count: count_nodes(&tree.root_node()),
                    error_count: 0,
                    warnings: Vec::new(),
                };

                let cache_entry = AstCacheEntry {
                    ast: tree.clone(),
                    metadata: metadata.clone(),
                    created_at: std::time::Instant::now(),
                    access_count: std::sync::atomic::AtomicU64::new(1),
                };
                AST_CACHE.insert(cache_key, Arc::new(cache_entry));

                let ast_resource = AstResource {
                    tree,
                    source_code,
                    language,
                    file_path,
                    metadata,
                };
                Ok(ResourceArc::new(ast_resource))
            }
            None => Err("Parse failed".to_string())
        }
    } else {
        Err("Unsupported language".to_string())
    }
}

#[rustler::nif]
fn parse_source_code(
    language: String,
    source_code: String,
    file_path: Option<String>
) -> NifResult<ResourceArc<AstResource>> {
    match internal_parse_source_code(language, source_code, file_path) {
        Ok(result) => Ok(result),
        Err(err) => Err(rustler::Error::Term(Box::new(err)))
    }
}

#[rustler::nif]
fn parse_file_batch(file_specs: Vec<(String, String)>) -> NifResult<Vec<String>> {
    let results: Vec<String> = file_specs
        .par_iter()
        .map(|(file_path, language)| {
            match std::fs::read_to_string(file_path) {
                Ok(source_code) => {
                    match internal_parse_source_code(language.clone(), source_code, Some(file_path.clone())) {
                        Ok(_ast_resource) => serde_json::json!({
                            "file_path": file_path,
                            "status": "success"
                        }).to_string(),
                        Err(err) => serde_json::json!({
                            "file_path": file_path,
                            "status": "error",
                            "error": err
                        }).to_string(),
                    }
                }
                Err(e) => serde_json::json!({
                    "file_path": file_path,
                    "status": "error",
                    "error": format!("Failed to read file: {}", e)
                }).to_string(),
            }
        })
        .collect();

    Ok(results)
}

#[rustler::nif]
fn query_ast_patterns(
    ast: ResourceArc<AstResource>,
    query_pattern: String
) -> NifResult<Vec<String>> {
    if let Some(&language) = LANGUAGE_REGISTRY.get(&ast.language) {
        match Query::new(language, &query_pattern) {
            Ok(query) => {
                let mut cursor = QueryCursor::new();
                let matches = cursor.matches(&query, ast.tree.root_node(), ast.source_code.as_bytes());
                
                let results: Vec<String> = matches
                    .map(|mat| {
                        let captures: Vec<_> = mat.captures
                            .iter()
                            .map(|cap| {
                                serde_json::json!({
                                    "text": cap.node.utf8_text(ast.source_code.as_bytes()).unwrap_or(""),
                                    "start": cap.node.start_byte(),
                                    "end": cap.node.end_byte(),
                                    "row": cap.node.start_position().row,
                                    "column": cap.node.start_position().column
                                })
                            })
                            .collect();
                        
                        serde_json::json!({
                            "captures": captures
                        }).to_string()
                    })
                    .collect();
                
                Ok(results)
            }
            Err(e) => Err(rustler::Error::Term(Box::new(format!("Query error: {}", e)))),
        }
    } else {
        Err(rustler::Error::Term(Box::new("Unsupported language")))
    }
}

#[rustler::nif]
fn extract_symbols(ast: ResourceArc<AstResource>) -> NifResult<Vec<String>> {
    let symbols = extract_symbols_from_ast(&ast.tree.root_node(), &ast.source_code, &ast.language);
    
    let results: Vec<String> = symbols
        .into_iter()
        .filter_map(|symbol| serde_json::to_string(&symbol).ok())
        .collect();
    
    Ok(results)
}

#[rustler::nif]
fn analyze_complexity(ast: ResourceArc<AstResource>) -> NifResult<String> {
    let metrics = calculate_complexity_metrics(&ast.tree.root_node(), &ast.source_code, &ast.language);
    
    match serde_json::to_string(&metrics) {
        Ok(json) => Ok(json),
        Err(e) => Err(rustler::Error::Term(Box::new(format!("Serialization error: {}", e)))),
    }
}

#[rustler::nif]
fn check_architectural_rules(
    ast: ResourceArc<AstResource>,
    rules_json: String
) -> NifResult<Vec<String>> {
    let rules: Vec<ArchitecturalRule> = match serde_json::from_str(&rules_json) {
        Ok(rules) => rules,
        Err(e) => return Err(rustler::Error::Term(Box::new(format!("Invalid rules JSON: {}", e)))),
    };

    if let Err(e) = RULES_ENGINE.add_rules(rules) {
        return Err(rustler::Error::Term(Box::new(e)));
    }

    let file_path = ast.file_path.as_deref().unwrap_or("");
    let violations = RULES_ENGINE.check_violations(&ast.tree, &ast.source_code, file_path, &ast.language);
    
    let results: Vec<String> = violations
        .into_iter()
        .filter_map(|violation| serde_json::to_string(&violation).ok())
        .collect();
    
    Ok(results)
}

#[rustler::nif]
fn get_ast_statistics(ast: ResourceArc<AstResource>) -> NifResult<String> {
    let stats = serde_json::json!({
        "node_count": ast.metadata.node_count,
        "error_count": ast.metadata.error_count,
        "parse_time_us": ast.metadata.parse_time_us,
        "source_length": ast.source_code.len(),
        "language": ast.language,
        "warnings": ast.metadata.warnings
    });
    
    Ok(stats.to_string())
}

#[rustler::nif]
fn compress_ast(ast: ResourceArc<AstResource>) -> NifResult<OwnedBinary> {
    let serialized = serde_json::to_vec(&convert_tree_to_ast_node(&ast.tree.root_node(), &ast.source_code))
        .map_err(|e| rustler::Error::Term(Box::new(format!("Serialization error: {}", e))))?;
    
    let compressed = compress_prepend_size(&serialized);
    
    let mut binary = OwnedBinary::new(compressed.len()).unwrap();
    binary.as_mut_slice().copy_from_slice(&compressed);
    
    Ok(binary)
}

#[rustler::nif]
fn decompress_ast(compressed_data: Binary) -> NifResult<String> {
    let decompressed = decompress_size_prepended(compressed_data.as_slice())
        .map_err(|e| rustler::Error::Term(Box::new(format!("Decompression error: {}", e))))?;
    
    let ast_node: AstNode = serde_json::from_slice(&decompressed)
        .map_err(|e| rustler::Error::Term(Box::new(format!("Deserialization error: {}", e))))?;
    
    serde_json::to_string(&ast_node)
        .map_err(|e| rustler::Error::Term(Box::new(format!("JSON error: {}", e))))
}

#[rustler::nif]
fn build_dependency_graph(file_paths: Vec<String>) -> NifResult<Vec<String>> {
    let dependency_graph = build_project_dependency_graph(file_paths);
    
    let results: Vec<String> = dependency_graph
        .into_iter()
        .filter_map(|node| serde_json::to_string(&node).ok())
        .collect();
    
    Ok(results)
}

#[rustler::nif]
fn validate_code_quality(ast: ResourceArc<AstResource>) -> NifResult<Vec<String>> {
    let quality_issues = analyze_code_quality(&ast.tree.root_node(), &ast.source_code, &ast.language);
    
    let results: Vec<String> = quality_issues
        .into_iter()
        .filter_map(|issue| serde_json::to_string(&issue).ok())
        .collect();
    
    Ok(results)
}

#[rustler::nif]
fn find_code_smells(ast: ResourceArc<AstResource>) -> NifResult<Vec<String>> {
    let code_smells = detect_code_smells(&ast.tree.root_node(), &ast.source_code, &ast.language);
    
    let results: Vec<String> = code_smells
        .into_iter()
        .filter_map(|smell| serde_json::to_string(&smell).ok())
        .collect();
    
    Ok(results)
}

#[rustler::nif]
fn extract_documentation(ast: ResourceArc<AstResource>) -> NifResult<Vec<String>> {
    let documentation = extract_doc_comments(&ast.tree.root_node(), &ast.source_code, &ast.language);
    
    let results: Vec<String> = documentation
        .into_iter()
        .map(|doc| serde_json::json!({
            "text": doc.text,
            "location": doc.location,
            "type": doc.doc_type
        }).to_string())
        .collect();
    
    Ok(results)
}

#[rustler::nif]
fn analyze_semantic_structure(ast: ResourceArc<AstResource>) -> NifResult<String> {
    let semantic_info = analyze_semantic_relationships(&ast.tree.root_node(), &ast.source_code, &ast.language);
    
    serde_json::to_string(&semantic_info)
        .map_err(|e| rustler::Error::Term(Box::new(format!("Serialization error: {}", e))))
}

// ============================================================================
// UTILITY FUNCTIONS - AST ANALYSIS
// ============================================================================

fn count_nodes(node: &Node) -> u32 {
    let mut count = 1;
    for child in node.children(&mut node.walk()) {
        count += count_nodes(&child);
    }
    count
}

fn count_error_nodes(node: &Node) -> u32 {
    let mut count = if node.is_error() { 1 } else { 0 };
    for child in node.children(&mut node.walk()) {
        count += count_error_nodes(&child);
    }
    count
}

fn convert_tree_to_ast_node(node: &Node, source_code: &str) -> AstNode {
    let children: Vec<AstNode> = node.children(&mut node.walk())
        .map(|child| convert_tree_to_ast_node(&child, source_code))
        .collect();

    AstNode {
        node_type: node.kind().to_string(),
        text: node.utf8_text(source_code.as_bytes()).unwrap_or("").to_string(),
        start_byte: node.start_byte() as u32,
        end_byte: node.end_byte() as u32,
        start_point: AstPoint {
            row: node.start_position().row as u32,
            column: node.start_position().column as u32,
        },
        end_point: AstPoint {
            row: node.end_position().row as u32,
            column: node.end_position().column as u32,
        },
        children,
        is_named: node.is_named(),
        field_name: None,
    }
}

fn extract_symbols_from_ast(node: &Node, source_code: &str, language: &str) -> Vec<SymbolInfo> {
    let mut symbols = Vec::new();
    
    match language {
        "javascript" | "typescript" => extract_js_symbols(node, source_code, &mut symbols),
        "python" => extract_python_symbols(node, source_code, &mut symbols),
        "rust" => extract_rust_symbols(node, source_code, &mut symbols),
        "elixir" => extract_elixir_symbols(node, source_code, &mut symbols),
        _ => extract_generic_symbols(node, source_code, &mut symbols),
    }
    
    symbols
}

fn extract_js_symbols(node: &Node, source_code: &str, symbols: &mut Vec<SymbolInfo>) {
    match node.kind() {
        "function_declaration" | "function_expression" | "arrow_function" => {
            if let Some(name_node) = node.child_by_field_name("name") {
                let name = name_node.utf8_text(source_code.as_bytes()).unwrap_or("").to_string();
                symbols.push(SymbolInfo {
                    name,
                    symbol_type: "function".to_string(),
                    location: AstPoint {
                        row: node.start_position().row as u32,
                        column: node.start_position().column as u32,
                    },
                    visibility: "public".to_string(),
                    documentation: extract_preceding_comment(node, source_code),
                    complexity: calculate_function_complexity(node),
                    dependencies: Vec::new(),
                });
            }
        }
        "class_declaration" => {
            if let Some(name_node) = node.child_by_field_name("name") {
                let name = name_node.utf8_text(source_code.as_bytes()).unwrap_or("").to_string();
                symbols.push(SymbolInfo {
                    name,
                    symbol_type: "class".to_string(),
                    location: AstPoint {
                        row: node.start_position().row as u32,
                        column: node.start_position().column as u32,
                    },
                    visibility: "public".to_string(),
                    documentation: extract_preceding_comment(node, source_code),
                    complexity: count_nodes(node),
                    dependencies: Vec::new(),
                });
            }
        }
        _ => {}
    }
    
    for child in node.children(&mut node.walk()) {
        extract_js_symbols(&child, source_code, symbols);
    }
}

fn extract_python_symbols(node: &Node, source_code: &str, symbols: &mut Vec<SymbolInfo>) {
    match node.kind() {
        "function_definition" => {
            if let Some(name_node) = node.child_by_field_name("name") {
                let name = name_node.utf8_text(source_code.as_bytes()).unwrap_or("").to_string();
                let visibility = determine_python_visibility(&name);
                symbols.push(SymbolInfo {
                    name,
                    symbol_type: "function".to_string(),
                    location: AstPoint {
                        row: node.start_position().row as u32,
                        column: node.start_position().column as u32,
                    },
                    visibility,
                    documentation: extract_python_docstring(node, source_code),
                    complexity: calculate_function_complexity(node),
                    dependencies: Vec::new(),
                });
            }
        }
        "class_definition" => {
            if let Some(name_node) = node.child_by_field_name("name") {
                let name = name_node.utf8_text(source_code.as_bytes()).unwrap_or("").to_string();
                let visibility = determine_python_visibility(&name);
                symbols.push(SymbolInfo {
                    name,
                    symbol_type: "class".to_string(),
                    location: AstPoint {
                        row: node.start_position().row as u32,
                        column: node.start_position().column as u32,
                    },
                    visibility,
                    documentation: extract_python_docstring(node, source_code),
                    complexity: count_nodes(node),
                    dependencies: Vec::new(),
                });
            }
        }
        _ => {}
    }
    
    for child in node.children(&mut node.walk()) {
        extract_python_symbols(&child, source_code, symbols);
    }
}

fn extract_rust_symbols(node: &Node, source_code: &str, symbols: &mut Vec<SymbolInfo>) {
    match node.kind() {
        "function_item" => {
            if let Some(name_node) = node.child_by_field_name("name") {
                let name = name_node.utf8_text(source_code.as_bytes()).unwrap_or("").to_string();
                symbols.push(SymbolInfo {
                    name,
                    symbol_type: "function".to_string(),
                    location: AstPoint {
                        row: node.start_position().row as u32,
                        column: node.start_position().column as u32,
                    },
                    visibility: extract_rust_visibility(node, source_code),
                    documentation: extract_rust_doc_comment(node, source_code),
                    complexity: calculate_function_complexity(node),
                    dependencies: Vec::new(),
                });
            }
        }
        "struct_item" | "enum_item" | "impl_item" => {
            if let Some(name_node) = node.child_by_field_name("name") {
                let name = name_node.utf8_text(source_code.as_bytes()).unwrap_or("").to_string();
                symbols.push(SymbolInfo {
                    name,
                    symbol_type: node.kind().replace("_item", ""),
                    location: AstPoint {
                        row: node.start_position().row as u32,
                        column: node.start_position().column as u32,
                    },
                    visibility: extract_rust_visibility(node, source_code),
                    documentation: extract_rust_doc_comment(node, source_code),
                    complexity: count_nodes(node),
                    dependencies: Vec::new(),
                });
            }
        }
        _ => {}
    }
    
    for child in node.children(&mut node.walk()) {
        extract_rust_symbols(&child, source_code, symbols);
    }
}

fn extract_elixir_symbols(node: &Node, source_code: &str, symbols: &mut Vec<SymbolInfo>) {
    match node.kind() {
        "call" => {
            if let Some(target) = node.child(0) {
                if target.kind() == "identifier" {
                    let target_text = target.utf8_text(source_code.as_bytes()).unwrap_or("");
                    if target_text == "def" || target_text == "defp" {
                        if let Some(name_node) = node.child(1) {
                            let name = name_node.utf8_text(source_code.as_bytes()).unwrap_or("").to_string();
                            symbols.push(SymbolInfo {
                                name,
                                symbol_type: "function".to_string(),
                                location: AstPoint {
                                    row: node.start_position().row as u32,
                                    column: node.start_position().column as u32,
                                },
                                visibility: if target_text == "defp" { "private".to_string() } else { "public".to_string() },
                                documentation: extract_elixir_doc(node, source_code),
                                complexity: calculate_function_complexity(node),
                                dependencies: Vec::new(),
                            });
                        }
                    }
                }
            }
        }
        _ => {}
    }
    
    for child in node.children(&mut node.walk()) {
        extract_elixir_symbols(&child, source_code, symbols);
    }
}

fn extract_generic_symbols(node: &Node, source_code: &str, symbols: &mut Vec<SymbolInfo>) {
    // Generic symbol extraction for unsupported languages
    if node.is_named() && !node.utf8_text(source_code.as_bytes()).unwrap_or("").trim().is_empty() {
        let text = node.utf8_text(source_code.as_bytes()).unwrap_or("").to_string();
        if text.len() < 100 && text.lines().count() == 1 {
            symbols.push(SymbolInfo {
                name: text,
                symbol_type: node.kind().to_string(),
                location: AstPoint {
                    row: node.start_position().row as u32,
                    column: node.start_position().column as u32,
                },
                visibility: "unknown".to_string(),
                documentation: None,
                complexity: 1,
                dependencies: Vec::new(),
            });
        }
    }
    
    for child in node.children(&mut node.walk()) {
        extract_generic_symbols(&child, source_code, symbols);
    }
}

fn calculate_complexity_metrics(node: &Node, source_code: &str, language: &str) -> ComplexityMetrics {
    let mut metrics = ComplexityMetrics {
        cyclomatic_complexity: 1,
        cognitive_complexity: 0,
        nesting_depth: 0,
        function_count: 0,
        class_count: 0,
        lines_of_code: source_code.lines().count() as u32,
        comment_ratio: calculate_comment_ratio(source_code, language),
    };

    calculate_complexity_recursive(node, source_code, &mut metrics, 0);
    metrics
}

fn calculate_complexity_recursive(node: &Node, source_code: &str, metrics: &mut ComplexityMetrics, current_depth: u32) {
    metrics.nesting_depth = metrics.nesting_depth.max(current_depth);

    match node.kind() {
        // Control flow nodes that increase cyclomatic complexity
        "if_statement" | "while_statement" | "for_statement" | "switch_statement" |
        "case_clause" | "catch_clause" | "conditional_expression" => {
            metrics.cyclomatic_complexity += 1;
            metrics.cognitive_complexity += current_depth + 1;
        }
        // Function/method declarations
        "function_declaration" | "function_expression" | "arrow_function" |
        "function_definition" | "function_item" | "method_definition" => {
            metrics.function_count += 1;
        }
        // Class declarations
        "class_declaration" | "class_definition" | "struct_item" => {
            metrics.class_count += 1;
        }
        _ => {}
    }

    for child in node.children(&mut node.walk()) {
        let child_depth = if is_nesting_node(&child) { current_depth + 1 } else { current_depth };
        calculate_complexity_recursive(&child, source_code, metrics, child_depth);
    }
}

fn calculate_function_complexity(node: &Node) -> u32 {
    let mut complexity = 1;
    
    for child in node.children(&mut node.walk()) {
        match child.kind() {
            "if_statement" | "while_statement" | "for_statement" | "switch_statement" |
            "case_clause" | "catch_clause" | "conditional_expression" => {
                complexity += 1;
            }
            _ => {}
        }
        complexity += calculate_function_complexity(&child);
    }
    
    complexity
}

fn is_nesting_node(node: &Node) -> bool {
    matches!(node.kind(), 
        "if_statement" | "while_statement" | "for_statement" | "switch_statement" |
        "try_statement" | "catch_clause" | "function_declaration" | "function_expression" |
        "class_declaration" | "method_definition" | "block_statement" | "compound_statement"
    )
}

fn calculate_comment_ratio(source_code: &str, language: &str) -> f64 {
    let total_lines = source_code.lines().count();
    if total_lines == 0 {
        return 0.0;
    }

    let comment_patterns = match language {
        "javascript" | "typescript" | "rust" | "go" => vec![r"^\s*//", r"^\s*/\*", r"^\s*\*/"],
        "python" => vec![r"^\s*#", r#"^\s*"""#, r#"^\s*'''"#],
        "elixir" => vec![r"^\s*#"],
        _ => vec![r"^\s*#", r"^\s*//"],
    };

    let mut comment_lines = 0;
    for line in source_code.lines() {
        for pattern in &comment_patterns {
            if let Ok(regex) = Regex::new(pattern) {
                if regex.is_match(line) {
                    comment_lines += 1;
                    break;
                }
            }
        }
    }

    comment_lines as f64 / total_lines as f64
}

fn extract_preceding_comment(node: &Node, source_code: &str) -> Option<String> {
    let start_row = node.start_position().row;
    if start_row == 0 {
        return None;
    }

    let lines: Vec<&str> = source_code.lines().collect();
    let mut comment_lines = Vec::new();
    let mut current_row = start_row.saturating_sub(1);

    while current_row > 0 {
        let line = lines.get(current_row)?.trim();
        if line.starts_with("//") || line.starts_with("/*") || line.starts_with("*") {
            comment_lines.insert(0, line.trim_start_matches("//").trim_start_matches("/*").trim_start_matches("*").trim());
            current_row = current_row.saturating_sub(1);
        } else if line.is_empty() {
            current_row = current_row.saturating_sub(1);
        } else {
            break;
        }
    }

    if comment_lines.is_empty() {
        None
    } else {
        Some(comment_lines.join(" "))
    }
}

fn determine_python_visibility(name: &str) -> String {
    if name.starts_with("__") && name.ends_with("__") {
        "magic".to_string()
    } else if name.starts_with("__") {
        "private".to_string()
    } else if name.starts_with("_") {
        "protected".to_string()
    } else {
        "public".to_string()
    }
}

fn extract_python_docstring(node: &Node, source_code: &str) -> Option<String> {
    // Look for string literal as first statement in function/class body
    for child in node.children(&mut node.walk()) {
        if child.kind() == "block" || child.kind() == "suite" {
            for grandchild in child.children(&mut child.walk()) {
                if grandchild.kind() == "expression_statement" {
                    for ggchild in grandchild.children(&mut grandchild.walk()) {
                        if ggchild.kind() == "string" {
                            let text = ggchild.utf8_text(source_code.as_bytes()).unwrap_or("");
                            if text.starts_with("\"\"\"") || text.starts_with("'''") {
                                return Some(text.trim_matches('"').trim_matches('\'').trim().to_string());
                            }
                        }
                    }
                }
            }
        }
    }
    None
}

fn extract_rust_visibility(node: &Node, source_code: &str) -> String {
    for child in node.children(&mut node.walk()) {
        if child.kind() == "visibility_modifier" {
            let vis_text = child.utf8_text(source_code.as_bytes()).unwrap_or("");
            return vis_text.to_string();
        }
    }
    "private".to_string()
}

fn extract_rust_doc_comment(node: &Node, source_code: &str) -> Option<String> {
    let start_row = node.start_position().row;
    if start_row == 0 {
        return None;
    }

    let lines: Vec<&str> = source_code.lines().collect();
    let mut doc_lines = Vec::new();
    let mut current_row = start_row.saturating_sub(1);

    while current_row > 0 {
        let line = lines.get(current_row)?.trim();
        if line.starts_with("///") {
            doc_lines.insert(0, line.trim_start_matches("///").trim());
            current_row = current_row.saturating_sub(1);
        } else if line.is_empty() {
            current_row = current_row.saturating_sub(1);
        } else {
            break;
        }
    }

    if doc_lines.is_empty() {
        None
    } else {
        Some(doc_lines.join(" "))
    }
}

fn extract_elixir_doc(node: &Node, source_code: &str) -> Option<String> {
    let start_row = node.start_position().row;
    if start_row == 0 {
        return None;
    }

    let lines: Vec<&str> = source_code.lines().collect();
    let mut current_row = start_row.saturating_sub(1);

    while current_row > 0 {
        let line = lines.get(current_row)?.trim();
        if line.starts_with("@doc") {
            // Extract the string after @doc
            if let Some(doc_start) = line.find('"') {
                return Some(line[doc_start..].trim_matches('"').to_string());
            }
        } else if line.is_empty() {
            current_row = current_row.saturating_sub(1);
        } else {
            break;
        }
    }

    None
}

fn build_project_dependency_graph(file_paths: Vec<String>) -> Vec<DependencyNode> {
    let mut nodes = Vec::new();
    
    // This is a simplified implementation
    for file_path in file_paths {
        nodes.push(DependencyNode {
            name: std::path::Path::new(&file_path)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .to_string(),
            file_path: file_path.clone(),
            dependencies: Vec::new(),
            dependents: Vec::new(),
            weight: 1.0,
            centrality: 0.0,
        });
    }
    
    nodes
}

fn analyze_code_quality(node: &Node, source_code: &str, language: &str) -> Vec<serde_json::Value> {
    let mut issues = Vec::new();
    
    // Check for common code quality issues
    let complexity = calculate_complexity_metrics(node, source_code, language);
    
    if complexity.cyclomatic_complexity > 10 {
        issues.push(serde_json::json!({
            "type": "high_complexity",
            "severity": "warning",
            "message": format!("High cyclomatic complexity: {}", complexity.cyclomatic_complexity),
            "location": {
                "row": 0,
                "column": 0
            }
        }));
    }
    
    if complexity.comment_ratio < 0.1 {
        issues.push(serde_json::json!({
            "type": "low_documentation",
            "severity": "info",
            "message": format!("Low comment ratio: {:.1}%", complexity.comment_ratio * 100.0),
            "location": {
                "row": 0,
                "column": 0
            }
        }));
    }
    
    issues
}

fn detect_code_smells(node: &Node, source_code: &str, language: &str) -> Vec<CodeSmell> {
    let mut smells = Vec::new();
    
    detect_code_smells_recursive(node, source_code, language, &mut smells, 0);
    
    smells
}

fn detect_code_smells_recursive(node: &Node, source_code: &str, language: &str, smells: &mut Vec<CodeSmell>, depth: u32) {
    // Long method detection
    if matches!(node.kind(), "function_declaration" | "function_definition" | "function_item") {
        let lines = node.end_position().row - node.start_position().row + 1;
        if lines > 50 {
            smells.push(CodeSmell {
                smell_type: "long_method".to_string(),
                severity: "warning".to_string(),
                description: format!("Method is {} lines long, consider breaking it down", lines),
                location: AstPoint {
                    row: node.start_position().row as u32,
                    column: node.start_position().column as u32,
                },
                metrics: {
                    let mut metrics = HashMap::new();
                    metrics.insert("lines".to_string(), lines as f64);
                    metrics
                },
            });
        }
    }
    
    // Deep nesting detection
    if depth > 5 {
        smells.push(CodeSmell {
            smell_type: "deep_nesting".to_string(),
            severity: "warning".to_string(),
            description: format!("Code is nested {} levels deep", depth),
            location: AstPoint {
                row: node.start_position().row as u32,
                column: node.start_position().column as u32,
            },
            metrics: {
                let mut metrics = HashMap::new();
                metrics.insert("nesting_depth".to_string(), depth as f64);
                metrics
            },
        });
    }
    
    let new_depth = if is_nesting_node(node) { depth + 1 } else { depth };
    for child in node.children(&mut node.walk()) {
        detect_code_smells_recursive(&child, source_code, language, smells, new_depth);
    }
}

#[derive(Debug, Clone)]
struct DocComment {
    text: String,
    location: AstPoint,
    doc_type: String,
}

fn extract_doc_comments(node: &Node, source_code: &str, language: &str) -> Vec<DocComment> {
    let mut docs = Vec::new();
    
    match language {
        "rust" => extract_rust_doc_comments(node, source_code, &mut docs),
        "javascript" | "typescript" => extract_js_doc_comments(node, source_code, &mut docs),
        "python" => extract_python_doc_comments(node, source_code, &mut docs),
        _ => {}
    }
    
    docs
}

fn extract_rust_doc_comments(node: &Node, source_code: &str, docs: &mut Vec<DocComment>) {
    let lines: Vec<&str> = source_code.lines().collect();
    let start_row = node.start_position().row;
    
    if start_row > 0 {
        let mut current_row = start_row.saturating_sub(1);
        let mut doc_lines = Vec::new();
        
        while current_row < lines.len() {
            let line = lines[current_row].trim();
            if line.starts_with("///") {
                doc_lines.insert(0, line.trim_start_matches("///").trim());
                if current_row == 0 { break; }
                current_row = current_row.saturating_sub(1);
            } else if line.is_empty() {
                if current_row == 0 { break; }
                current_row = current_row.saturating_sub(1);
            } else {
                break;
            }
        }
        
        if !doc_lines.is_empty() {
            docs.push(DocComment {
                text: doc_lines.join(" "),
                location: AstPoint {
                    row: start_row as u32,
                    column: node.start_position().column as u32,
                },
                doc_type: "rust_doc_comment".to_string(),
            });
        }
    }
    
    for child in node.children(&mut node.walk()) {
        extract_rust_doc_comments(&child, source_code, docs);
    }
}

fn extract_js_doc_comments(node: &Node, source_code: &str, docs: &mut Vec<DocComment>) {
    // Similar implementation for JavaScript JSDoc comments
    for child in node.children(&mut node.walk()) {
        extract_js_doc_comments(&child, source_code, docs);
    }
}

fn extract_python_doc_comments(node: &Node, source_code: &str, docs: &mut Vec<DocComment>) {
    // Similar implementation for Python docstrings
    for child in node.children(&mut node.walk()) {
        extract_python_doc_comments(&child, source_code, docs);
    }
}

fn analyze_semantic_relationships(node: &Node, source_code: &str, language: &str) -> serde_json::Value {
    let mut relationships = HashMap::new();
    
    // Count different types of semantic relationships
    count_semantic_relationships(node, source_code, &mut relationships);
    
    serde_json::json!({
        "relationships": relationships,
        "total_nodes": count_nodes(node),
        "language": language,
        "analysis_depth": calculate_max_depth(node, 0)
    })
}

fn count_semantic_relationships(node: &Node, source_code: &str, relationships: &mut HashMap<String, u32>) {
    let node_type = node.kind();
    *relationships.entry(node_type.to_string()).or_insert(0) += 1;
    
    for child in node.children(&mut node.walk()) {
        count_semantic_relationships(&child, source_code, relationships);
    }
}

fn calculate_max_depth(node: &Node, current_depth: u32) -> u32 {
    let mut max_depth = current_depth;
    
    for child in node.children(&mut node.walk()) {
        let child_depth = calculate_max_depth(&child, current_depth + 1);
        max_depth = max_depth.max(child_depth);
    }
    
    max_depth
}