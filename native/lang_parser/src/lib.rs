#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

use rustler::{Atom, Binary, Encoder, Env, NifResult, NifStruct, Resource, Term};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::sync::Arc;
use rayon::prelude::*;
use dashmap::DashMap;
use once_cell::sync::Lazy;
use aho_corasick::AhoCorasick;
use fancy_regex::Regex as FancyRegex;
use unicode_segmentation::UnicodeSegmentation;

mod parsers;
mod analysis;
mod stylometrics;
mod performance;
mod semantic_diff;
mod streaming_parser;

use parsers::{Parser, MarkdownParser, JsonParser, TextParser};
use analysis::{analyze_full_text, calculate_complexity_score, calculate_readability_score};
use stylometrics::{analyze_writing_style, compare_styles};
use semantic_diff::{SemanticDiffEngine, SemanticDiffConfig, TripleDiff, SemanticDiffError};
use streaming_parser::{StreamingJsonLdParser, StreamingConfig, JsonLdNode, StreamingError};

// Atoms for Elixir communication
rustler::atoms! {
    ok,
    error,
    unsupported_format,
    timeout,
    memory_error,
    
    // Analysis types
    markdown,
    javascript,
    python,
    elixir,
    typescript,
    rust,
    go,
    json,
    yaml,
    text,
    conversation,
    email,
    
    // Operation types
    parse,
    analyze,
    fingerprint,
    obfuscate,
    compare,
    
    // Error types
    invalid_input,
    parser_error,
    analysis_error,
    resource_exhausted,
}

// High-performance cache for parsed content
static PARSE_CACHE: Lazy<DashMap<u64, Arc<ParsedContent>>> = Lazy::new(|| DashMap::new());
static PATTERN_CACHE: Lazy<DashMap<String, Arc<CompiledPatterns>>> = Lazy::new(|| DashMap::new());

#[derive(NifStruct, Clone, Debug)]
#[module = "Lang.Native.ParseResult"]
pub struct ParseResult {
    pub format: String,
    pub tokens: Vec<String>,
    pub ast_nodes: u32,
    pub complexity_score: f64,
    pub readability_score: f64,
    pub line_count: u32,
    pub word_count: u32,
    pub char_count: u32,
    pub functions: Vec<String>,
    pub classes: Vec<String>,
    pub imports: Vec<String>,
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
    pub suggestions: Vec<String>,
    pub processing_time_us: u64,
}

#[derive(NifStruct, Clone, Debug)]
#[module = "Lang.Native.SemanticDiff"]
pub struct SemanticDiffResult {
    pub additions: u32,
    pub deletions: u32,
    pub modifications: u32,
    pub context_changes: Vec<String>,
    pub processing_time_us: u64,
}

#[derive(NifStruct, Clone, Debug)]
#[module = "Lang.Native.StreamingResult"]
pub struct StreamingResult {
    pub nodes_extracted: u32,
    pub bytes_processed: u64,
    pub parsing_errors: Vec<String>,
    pub processing_time_us: u64,
}

#[derive(NifStruct, Clone, Debug)]
#[module = "Lang.Native.StyleAnalysis"]
pub struct StyleAnalysis {
    pub fingerprint_hash: String,
    pub fingerprint_vector: Vec<f64>,
    pub linguistic_features: HashMap<String, f64>,
    pub syntactic_features: HashMap<String, f64>,
    pub lexical_features: HashMap<String, f64>,
    pub confidence_score: f64,
    pub processing_time_us: u64,
}

#[derive(NifStruct, Clone, Debug)]
#[module = "Lang.Native.ComparisonResult"]
pub struct ComparisonResult {
    pub similarity_score: f64,
    pub likely_same_author: bool,
    pub confidence_level: String,
    pub feature_differences: HashMap<String, f64>,
    pub distinctive_markers: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct ParsedContent {
    pub format: String,
    pub content: String,
    pub tokens: Vec<String>,
    pub metadata: HashMap<String, serde_json::Value>,
    pub cached_at: std::time::Instant,
}

#[derive(Debug, Clone)]
pub struct CompiledPatterns {
    pub regex_patterns: Vec<FancyRegex>,
    pub aho_corasick: Option<AhoCorasick>,
    pub compiled_at: std::time::Instant,
}

struct ParserResource {
    parser_type: String,
    tree_sitter_parser: Option<tree_sitter::Parser>,
}



// === MAIN NIF FUNCTIONS ===

// Private helper function for content parsing
fn parse_content_impl(content: String, format: String, _options: HashMap<String, Term>) -> NifResult<ParseResult> {
    let start_time = std::time::Instant::now();
    
    // Early validation
    if content.is_empty() {
        return Ok(ParseResult {
            format: format.clone(),
            tokens: vec![],
            ast_nodes: 0,
            complexity_score: 0.0,
            readability_score: 0.0,
            line_count: 0,
            word_count: 0,
            char_count: 0,
            functions: vec![],
            classes: vec![],
            imports: vec![],
            errors: vec![],
            warnings: vec![],
            suggestions: vec![],
            processing_time_us: start_time.elapsed().as_micros() as u64,
        });
    }
    
    // Check cache first
    let content_hash = calculate_hash(&content, &format);
    if let Some(cached) = PARSE_CACHE.get(&content_hash) {
        if cached.cached_at.elapsed().as_secs() < 300 { // 5 minute cache
            return build_parse_result_from_cached(&cached, start_time);
        }
    }
    
    // Route to appropriate high-performance parser
    let parser_result = match format.as_str() {
        "markdown" | "md" => {
            let parser = MarkdownParser::new();
            Parser::parse(&parser, &content)
        },
        "json" => {
            let parser = JsonParser::new();
            Parser::parse(&parser, &content)
        },
        "text" | "txt" | _ => {
            let parser = TextParser::new();
            Parser::parse(&parser, &content)
        },
    };
    
    let result = convert_parse_result_to_legacy(parser_result);
    
    // Cache the result
    let parsed_content = Arc::new(ParsedContent {
        format: format.clone(),
        content: content.clone(),
        tokens: result.tokens.clone(),
        metadata: HashMap::new(),
        cached_at: std::time::Instant::now(),
    });
    PARSE_CACHE.insert(content_hash, parsed_content);
    
    // Clean cache periodically
    if PARSE_CACHE.len() > 10000 {
        clean_parse_cache();
    }
    
    Ok(result)
}

fn convert_parse_result_to_legacy(parser_result: parsers::ParseResult) -> ParseResult {
    ParseResult {
        format: parser_result.metadata.format,
        tokens: vec![], // Simplified for now
        ast_nodes: 0,
        complexity_score: 0.0,
        readability_score: 0.0,
        line_count: parser_result.content.lines().count() as u32,
        word_count: parser_result.content.split_whitespace().count() as u32,
        char_count: parser_result.content.chars().count() as u32,
        functions: vec![], // Simplified for now
        classes: vec![], // Simplified for now
        imports: vec![], // Simplified for now
        errors: parser_result.errors,
        warnings: parser_result.warnings,
        suggestions: vec![], // Simplified for now
        processing_time_us: parser_result.metadata.parse_time_ms * 1000,
    }
}

#[rustler::nif]
fn analyze_style(content: String, _options: HashMap<String, Term>) -> NifResult<StyleAnalysis> {
    let start_time = std::time::Instant::now();
    
    if content.len() < 10 {
        return Ok(StyleAnalysis {
            fingerprint_hash: String::new(),
            fingerprint_vector: vec![],
            linguistic_features: HashMap::new(),
            syntactic_features: HashMap::new(),
            lexical_features: HashMap::new(),
            confidence_score: 0.0,
            processing_time_us: start_time.elapsed().as_micros() as u64,
        });
    }
    
    // Use available stylometric analysis
    let style_profile = stylometrics::analyze_writing_style(&content);
    
    // Create feature maps from available data
    let mut linguistic_features = HashMap::new();
    linguistic_features.insert("avg_sentence_length".to_string(), style_profile.avg_sentence_length);
    linguistic_features.insert("vocabulary_richness".to_string(), style_profile.vocabulary_richness);
    linguistic_features.insert("function_word_ratio".to_string(), style_profile.function_word_ratio);
    
    let mut syntactic_features = HashMap::new();
    syntactic_features.insert("sentence_length_variance".to_string(), style_profile.sentence_length_variance);
    syntactic_features.insert("lexical_density".to_string(), style_profile.lexical_density);
    
    let mut lexical_features = HashMap::new();
    for (punct, freq) in &style_profile.punctuation_frequency {
        lexical_features.insert(format!("punct_{}", punct), *freq);
    }
    
    // Generate a simple hash from the style profile
    let mut hasher = DefaultHasher::new();
    style_profile.avg_sentence_length.to_bits().hash(&mut hasher);
    style_profile.vocabulary_richness.to_bits().hash(&mut hasher);
    style_profile.function_word_ratio.to_bits().hash(&mut hasher);
    let fingerprint_hash = format!("{:x}", hasher.finish());
    
    // Create fingerprint vector from key metrics
    let fingerprint_vector = vec![
        style_profile.avg_sentence_length,
        style_profile.vocabulary_richness,
        style_profile.function_word_ratio,
        style_profile.sentence_length_variance,
        style_profile.lexical_density,
    ];
    
    let confidence_score = 0.75; // Placeholder confidence
    
    Ok(StyleAnalysis {
        fingerprint_hash,
        fingerprint_vector,
        linguistic_features,
        syntactic_features: syntactic_features,
        lexical_features,
        confidence_score,
        processing_time_us: start_time.elapsed().as_micros() as u64,
    })
}

#[rustler::nif]
fn compare_styles(style1: StyleAnalysis, style2: StyleAnalysis) -> NifResult<ComparisonResult> {
    // Create dummy style profiles for comparison
    let profile1 = stylometrics::StyleProfile {
        avg_sentence_length: style1.linguistic_features.get("avg_sentence_length").unwrap_or(&20.0).clone(),
        vocabulary_richness: style1.linguistic_features.get("vocabulary_richness").unwrap_or(&0.5).clone(),
        punctuation_frequency: HashMap::new(),
        function_word_ratio: style1.linguistic_features.get("function_word_ratio").unwrap_or(&0.3).clone(),
        sentence_length_variance: style1.syntactic_features.get("sentence_length_variance").unwrap_or(&5.0).clone(),
        lexical_density: style1.syntactic_features.get("lexical_density").unwrap_or(&0.7).clone(),
    };
    let profile2 = stylometrics::StyleProfile {
        avg_sentence_length: style2.linguistic_features.get("avg_sentence_length").unwrap_or(&20.0).clone(),
        vocabulary_richness: style2.linguistic_features.get("vocabulary_richness").unwrap_or(&0.5).clone(),
        punctuation_frequency: HashMap::new(),
        function_word_ratio: style2.linguistic_features.get("function_word_ratio").unwrap_or(&0.3).clone(),
        sentence_length_variance: style2.syntactic_features.get("sentence_length_variance").unwrap_or(&5.0).clone(),
        lexical_density: style2.syntactic_features.get("lexical_density").unwrap_or(&0.7).clone(),
    };
    let comparison = stylometrics::compare_styles(&profile1, &profile2);
    let similarity = comparison.similarity_score;
    let likely_same = similarity > 0.75;
    let confidence_level = match similarity {
        s if s > 0.9 => "very_high".to_string(),
        s if s > 0.8 => "high".to_string(),
        s if s > 0.6 => "medium".to_string(),
        _ => "low".to_string(),
    };
    
    let differences = HashMap::new(); // Simplified for now
    let markers = comparison.differences;
    
    Ok(ComparisonResult {
        similarity_score: similarity,
        likely_same_author: likely_same,
        confidence_level,
        feature_differences: differences,
        distinctive_markers: markers,
    })
}

#[rustler::nif]
fn parse_content(content: String, format: String, options: HashMap<String, Term>) -> NifResult<ParseResult> {
    parse_content_impl(content, format, options)
}

#[rustler::nif]
fn batch_parse(contents: Vec<(String, String)>, options: HashMap<String, Term>) -> NifResult<Vec<ParseResult>> {
    // Sequential processing to avoid Send trait issues
    let mut parse_results = Vec::with_capacity(contents.len());
    
    for (content, format) in contents {
        match parse_content_impl(content, format.clone(), options.clone()) {
            Ok(parse_result) => parse_results.push(parse_result),
            Err(_) => {
                // Create error result instead of failing entire batch
                parse_results.push(ParseResult {
                    format: "error".to_string(),
                    tokens: vec![],
                    ast_nodes: 0,
                    complexity_score: 0.0,
                    readability_score: 0.0,
                    line_count: 0,
                    word_count: 0,
                    char_count: 0,
                    functions: vec![],
                    classes: vec![],
                    imports: vec![],
                    errors: vec!["Parse error".to_string()],
                    warnings: vec![],
                    suggestions: vec![],
                    processing_time_us: 0,
                });
            }
        }
    }
    
    Ok(parse_results)
}

#[rustler::nif]
fn obfuscate_text(content: String, intensity: f64, preserve_meaning: bool) -> NifResult<String> {
    if intensity < 0.0 || intensity > 1.0 {
        return Err(rustler::Error::BadArg);
    }
    
    // Simple obfuscation implementation
    let obfuscated = if preserve_meaning {
        // Light obfuscation - just change some characters
        content.chars().enumerate().map(|(i, c)| {
            if i % 3 == 0 && c.is_alphabetic() && intensity > 0.5 {
                match c.to_ascii_lowercase() {
                    'a' => 'e', 'e' => 'i', 'i' => 'o', 'o' => 'u', 'u' => 'a',
                    _ => c
                }
            } else {
                c
            }
        }).collect()
    } else {
        // Heavy obfuscation - replace with random-ish characters
        content.chars().map(|c| {
            if c.is_alphabetic() && intensity > 0.3 {
                if c.is_uppercase() { 'X' } else { 'x' }
            } else {
                c
            }
        }).collect()
    };
    
    Ok(obfuscated)
}

#[rustler::nif]
fn get_performance_stats() -> NifResult<HashMap<String, u64>> {
    let mut stats = HashMap::new();
    stats.insert("cache_size".to_string(), PARSE_CACHE.len() as u64);
    stats.insert("pattern_cache_size".to_string(), PATTERN_CACHE.len() as u64);
    stats.insert("memory_usage".to_string(), 0); // Memory usage placeholder
    stats.insert("cpu_usage".to_string(), 0.0 as u64);
    
    Ok(stats)
}

#[rustler::nif]
fn clear_caches() -> NifResult<Atom> {
    PARSE_CACHE.clear();
    PATTERN_CACHE.clear();
    Ok(ok())
}

#[rustler::nif]
fn semantic_diff(old_doc: String, new_doc: String, doc_id: String) -> NifResult<SemanticDiffResult> {
    let start_time = std::time::Instant::now();
    let config = SemanticDiffConfig::default();
    let engine = SemanticDiffEngine::new(config);
    
    match engine.compute_diff(&old_doc, &new_doc, &doc_id) {
        Ok(diff) => {
            Ok(SemanticDiffResult {
                additions: diff.additions.len() as u32,
                deletions: diff.deletions.len() as u32,
                modifications: diff.modifications.len() as u32,
                context_changes: diff.context_changes,
                processing_time_us: start_time.elapsed().as_micros() as u64,
            })
        }
        Err(e) => Err(rustler::Error::Term(Box::new(format!("Semantic diff error: {}", e))))
    }
}

#[rustler::nif]
fn stream_parse_jsonld(content: String, chunk_size: Option<u32>) -> NifResult<StreamingResult> {
    let start_time = std::time::Instant::now();
    
    let mut config = StreamingConfig::default();
    if let Some(size) = chunk_size {
        config.chunk_size = size as usize;
    }
    
    let mut parser = StreamingJsonLdParser::new(config);
    
    match parser.process_chunk(content.as_bytes()) {
        Ok(nodes) => {
            let stats = parser.get_stats();
            Ok(StreamingResult {
                nodes_extracted: nodes.len() as u32,
                bytes_processed: stats.total_bytes_processed as u64,
                parsing_errors: vec![], // Would collect actual errors
                processing_time_us: start_time.elapsed().as_micros() as u64,
            })
        }
        Err(e) => {
            Ok(StreamingResult {
                nodes_extracted: 0,
                bytes_processed: 0,
                parsing_errors: vec![e.to_string()],
                processing_time_us: start_time.elapsed().as_micros() as u64,
            })
        }
    }
}

#[rustler::nif]
fn stream_parse_file_mmap(file_path: String) -> NifResult<StreamingResult> {
    let start_time = std::time::Instant::now();
    let config = StreamingConfig::default();
    let mut parser = StreamingJsonLdParser::new(config);
    
    match parser.process_file_mmap(&file_path) {
        Ok(nodes) => {
            let stats = parser.get_stats();
            Ok(StreamingResult {
                nodes_extracted: nodes.len() as u32,
                bytes_processed: stats.total_bytes_processed as u64,
                parsing_errors: vec![],
                processing_time_us: start_time.elapsed().as_micros() as u64,
            })
        }
        Err(e) => {
            Ok(StreamingResult {
                nodes_extracted: 0,
                bytes_processed: 0,
                parsing_errors: vec![e.to_string()],
                processing_time_us: start_time.elapsed().as_micros() as u64,
            })
        }
    }
}

// === UTILITY FUNCTIONS ===

fn calculate_hash(content: &str, format: &str) -> u64 {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    
    let mut hasher = DefaultHasher::new();
    content.hash(&mut hasher);
    format.hash(&mut hasher);
    hasher.finish()
}

fn build_parse_result_from_cached(cached: &ParsedContent, start_time: std::time::Instant) -> NifResult<ParseResult> {
    Ok(ParseResult {
        format: cached.format.clone(),
        tokens: cached.tokens.clone(),
        ast_nodes: cached.tokens.len() as u32,
        complexity_score: 5.0, // Cached approximation
        readability_score: 7.0, // Cached approximation
        line_count: cached.content.lines().count() as u32,
        word_count: cached.content.split_whitespace().count() as u32,
        char_count: cached.content.len() as u32,
        functions: vec![], // Would be cached in full implementation
        classes: vec![],
        imports: vec![],
        errors: vec![],
        warnings: vec![],
        suggestions: vec![],
        processing_time_us: start_time.elapsed().as_micros() as u64,
    })
}

fn clean_parse_cache() {
    let now = std::time::Instant::now();
    PARSE_CACHE.retain(|_, v| now.duration_since(v.cached_at).as_secs() < 3600);
}

rustler::init!(
    "Elixir.Lang.Native.Parser",
    [
        parse_content,
        analyze_style,
        compare_styles,
        batch_parse,
        obfuscate_text,
        get_performance_stats,
        clear_caches,
        semantic_diff,
        stream_parse_jsonld,
        stream_parse_file_mmap
    ],
    load = on_load
);

fn on_load(env: Env, _info: Term) -> bool {
    rustler::resource!(ParserResource, env);
    true
}