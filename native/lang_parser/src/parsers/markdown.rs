use crate::ParseResult;
use pulldown_cmark::{Parser, Event, Tag, TagEnd, CowStr, CodeBlockKind};
use std::collections::HashMap;
use rustler::Term;
use fancy_regex::Regex;
use once_cell::sync::Lazy;
use rayon::prelude::*;

// Pre-compiled regexes for maximum performance
static LINK_REGEX: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"\[([^\]]+)\]\(([^)]+)\)").unwrap()
});

static CODE_BLOCK_REGEX: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"```(\w+)?\n(.*?)```").unwrap()
});

static EMPHASIS_REGEX: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"\*{1,3}([^*]+)\*{1,3}|_{1,3}([^_]+)_{1,3}").unwrap()
});

static LIST_ITEM_REGEX: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"^[\s]*[-*+]\s+(.+)$").unwrap()
});

static NUMBERED_LIST_REGEX: Lazy::new(|| {
    Regex::new(r"^[\s]*\d+\.\s+(.+)$").unwrap()
});

static TASK_LIST_REGEX: Lazy::new(|| {
    Regex::new(r"^[\s]*[-*+]\s+\[([x\s])\]\s+(.+)$").unwrap()
});

pub struct MarkdownMetrics {
    pub headers: Vec<HeaderInfo>,
    pub links: Vec<LinkInfo>,
    pub images: Vec<ImageInfo>,
    pub code_blocks: Vec<CodeBlockInfo>,
    pub tables: Vec<TableInfo>,
    pub lists: Vec<ListInfo>,
    pub emphasis_count: u32,
    pub blockquote_count: u32,
    pub footnote_count: u32,
    pub task_list_items: u32,
    pub total_words: u32,
    pub reading_time_minutes: f64,
}

#[derive(Clone, Debug)]
pub struct HeaderInfo {
    pub level: u8,
    pub text: String,
    pub anchor: String,
    pub line_number: u32,
}

#[derive(Clone, Debug)]
pub struct LinkInfo {
    pub text: String,
    pub url: String,
    pub is_external: bool,
    pub is_image: bool,
}

#[derive(Clone, Debug)]
pub struct ImageInfo {
    pub alt_text: String,
    pub url: String,
    pub title: Option<String>,
}

#[derive(Clone, Debug)]
pub struct CodeBlockInfo {
    pub language: Option<String>,
    pub content: String,
    pub line_count: u32,
    pub char_count: u32,
}

#[derive(Clone, Debug)]
pub struct TableInfo {
    pub headers: Vec<String>,
    pub rows: u32,
    pub columns: u32,
}

#[derive(Clone, Debug)]
pub struct ListInfo {
    pub list_type: ListType,
    pub items: Vec<String>,
    pub nested_level: u8,
}

#[derive(Clone, Debug)]
pub enum ListType {
    Unordered,
    Ordered,
    TaskList,
}

pub fn parse_markdown(content: &str, _options: &HashMap<String, Term>) -> Result<ParseResult, rustler::Error> {
    let start_time = std::time::Instant::now();

    // Fast path for empty content
    if content.trim().is_empty() {
        return Ok(create_empty_result("markdown".to_string(), start_time));
    }

    // Parse with pulldown-cmark for maximum speed
    let parser = Parser::new(content);
    let events: Vec<_> = parser.collect();

    // Parallel analysis of different markdown features
    let (metrics, tokens, complexity) = rayon::join3(
        || extract_markdown_metrics(content, &events),
        || tokenize_markdown_content(content),
        || calculate_markdown_complexity(content, &events),
    );

    // Calculate readability using Flesch-Kincaid
    let readability = calculate_markdown_readability(content, &metrics);

    // Extract structural elements
    let functions = extract_functions_from_code_blocks(&metrics.code_blocks);
    let classes = extract_classes_from_content(content);
    let imports = extract_imports_from_code_blocks(&metrics.code_blocks);

    // Generate intelligent suggestions
    let suggestions = generate_markdown_suggestions(content, &metrics);
    let warnings = generate_markdown_warnings(content, &metrics);

    let processing_time = start_time.elapsed().as_micros() as u64;

    Ok(ParseResult {
        format: "markdown".to_string(),
        tokens,
        ast_nodes: events.len() as u32,
        complexity_score: complexity,
        readability_score: readability,
        line_count: content.lines().count() as u32,
        word_count: metrics.total_words,
        char_count: content.len() as u32,
        functions,
        classes,
        imports,
        errors: vec![],
        warnings,
        suggestions,
        processing_time_us: processing_time,
    })
}

fn extract_markdown_metrics(content: &str, events: &[Event]) -> MarkdownMetrics {
    let mut metrics = MarkdownMetrics {
        headers: Vec::new(),
        links: Vec::new(),
        images: Vec::new(),
        code_blocks: Vec::new(),
        tables: Vec::new(),
        lists: Vec::new(),
        emphasis_count: 0,
        blockquote_count: 0,
        footnote_count: 0,
        task_list_items: 0,
        total_words: 0,
        reading_time_minutes: 0.0,
    };

    let mut current_header_level = 0;
    let mut current_header_text = String::new();
    let mut current_code_language: Option<String> = None;
    let mut current_code_content = String::new();
    let mut line_number = 1;

    // Process events for structural analysis
    for event in events {
        match event {
            Event::Start(Tag::Heading { level, .. }) => {
                current_header_level = *level as u8;
                current_header_text.clear();
            }
            Event::End(TagEnd::Heading(_)) => {
                if !current_header_text.is_empty() {
                    let anchor = slugify(&current_header_text);
                    metrics.headers.push(HeaderInfo {
                        level: current_header_level,
                        text: current_header_text.clone(),
                        anchor,
                        line_number,
                    });
                }
                current_header_text.clear();
            }
            Event::Text(text) => {
                if current_header_level > 0 {
                    current_header_text.push_str(text);
                }
                if !current_code_language.is_none() {
                    current_code_content.push_str(text);
                }
                metrics.total_words += text.split_whitespace().count() as u32;
            }
            Event::Start(Tag::CodeBlock(CodeBlockKind::Fenced(lang))) => {
                current_code_language = if lang.is_empty() {
                    None
                } else {
                    Some(lang.to_string())
                };
                current_code_content.clear();
            }
            Event::End(TagEnd::CodeBlock) => {
                metrics.code_blocks.push(CodeBlockInfo {
                    language: current_code_language.clone(),
                    content: current_code_content.clone(),
                    line_count: current_code_content.lines().count() as u32,
                    char_count: current_code_content.len() as u32,
                });
                current_code_language = None;
                current_code_content.clear();
            }
            Event::Start(Tag::Link { dest_url, .. }) => {
                let is_external = dest_url.starts_with("http");
                // Link text will be captured in subsequent Text events
            }
            Event::Start(Tag::Image { dest_url, title }) => {
                metrics.images.push(ImageInfo {
                    alt_text: String::new(), // Will be filled from subsequent events
                    url: dest_url.to_string(),
                    title: title.as_ref().map(|t| t.to_string()),
                });
            }
            Event::Start(Tag::Emphasis) | Event::Start(Tag::Strong) => {
                metrics.emphasis_count += 1;
            }
            Event::Start(Tag::BlockQuote) => {
                metrics.blockquote_count += 1;
            }
            Event::SoftBreak | Event::HardBreak => {
                line_number += 1;
            }
            _ => {}
        }
    }

    // Extract additional metrics using regex patterns
    extract_regex_metrics(content, &mut metrics);

    // Calculate reading time (average 200 words per minute)
    metrics.reading_time_minutes = metrics.total_words as f64 / 200.0;

    metrics
}

fn extract_regex_metrics(content: &str, metrics: &mut MarkdownMetrics) {
    // Count task list items
    for line in content.lines() {
        if TASK_LIST_REGEX.is_match(line).unwrap_or(false) {
            metrics.task_list_items += 1;
        }
    }

    // Extract links using regex for additional accuracy
    for captures in LINK_REGEX.captures_iter(content) {
        if let (Ok(Some(text)), Ok(Some(url))) = (captures.get(1), captures.get(2)) {
            let is_external = url.as_str().starts_with("http");
            metrics.links.push(LinkInfo {
                text: text.as_str().to_string(),
                url: url.as_str().to_string(),
                is_external,
                is_image: false,
            });
        }
    }
}

fn tokenize_markdown_content(content: &str) -> Vec<String> {
    // Advanced tokenization considering markdown syntax
    let mut tokens = Vec::new();

    // Split into lines and process each
    for line in content.lines() {
        // Skip markdown syntax and extract meaningful tokens
        let cleaned = line
            .trim()
            // Remove markdown headers
            .trim_start_matches('#')
            .trim()
            // Remove list markers
            .trim_start_matches(|c| c == '-' || c == '*' || c == '+')
            .trim()
            // Remove numbered list markers
            .split_once(". ")
            .map(|(_, rest)| rest)
            .unwrap_or(line.trim());

        if !cleaned.is_empty() {
            // Tokenize words, preserving important punctuation
            for word in cleaned.split_whitespace() {
                let clean_word = word
                    .trim_matches(|c: char| c.is_ascii_punctuation() && c != '.' && c != '!' && c != '?')
                    .to_lowercase();

                if !clean_word.is_empty() && clean_word.len() > 1 {
                    tokens.push(clean_word);
                }
            }
        }
    }

    tokens
}

fn calculate_markdown_complexity(content: &str, events: &[Event]) -> f64 {
    let mut complexity = 1.0;

    // Base complexity factors
    let line_count = content.lines().count();
    let event_count = events.len();

    // Structural complexity
    let header_count = events.iter()
        .filter(|e| matches!(e, Event::Start(Tag::Heading { .. })))
        .count();

    let list_count = events.iter()
        .filter(|e| matches!(e, Event::Start(Tag::List(_))))
        .count();

    let table_count = events.iter()
        .filter(|e| matches!(e, Event::Start(Tag::Table(_))))
        .count();

    let code_block_count = events.iter()
        .filter(|e| matches!(e, Event::Start(Tag::CodeBlock(_))))
        .count();

    // Calculate weighted complexity
    complexity += (line_count as f64 * 0.01);
    complexity += (event_count as f64 * 0.05);
    complexity += (header_count as f64 * 0.1);
    complexity += (list_count as f64 * 0.15);
    complexity += (table_count as f64 * 0.3);
    complexity += (code_block_count as f64 * 0.4);

    // Nested structure penalty
    let nesting_depth = calculate_nesting_depth(events);
    complexity += (nesting_depth as f64 * 0.2);

    complexity.min(10.0)
}

fn calculate_nesting_depth(events: &[Event]) -> u32 {
    let mut max_depth = 0;
    let mut current_depth = 0;

    for event in events {
        match event {
            Event::Start(_) => {
                current_depth += 1;
                max_depth = max_depth.max(current_depth);
            }
            Event::End(_) => {
                current_depth = current_depth.saturating_sub(1);
            }
            _ => {}
        }
    }

    max_depth
}

fn calculate_markdown_readability(content: &str, metrics: &MarkdownMetrics) -> f64 {
    if metrics.total_words == 0 {
        return 0.0;
    }

    let sentences = count_sentences(content);
    let syllables = estimate_syllables(content);

    if sentences == 0 {
        return 5.0;
    }

    // Flesch Reading Ease Score
    let avg_sentence_length = metrics.total_words as f64 / sentences as f64;
    let avg_syllables_per_word = syllables as f64 / metrics.total_words as f64;

    let flesch_score = 206.835 - (1.015 * avg_sentence_length) - (84.6 * avg_syllables_per_word);

    // Convert to 0-10 scale and adjust for markdown complexity
    let base_score = (flesch_score / 10.0).max(0.0).min(10.0);

    // Bonus for good markdown structure
    let structure_bonus = if metrics.headers.len() > 2 { 0.5 } else { 0.0 };
    let list_bonus = if metrics.lists.len() > 0 { 0.3 } else { 0.0 };

    (base_score + structure_bonus + list_bonus).min(10.0)
}

fn count_sentences(content: &str) -> u32 {
    content.matches(|c| c == '.' || c == '!' || c == '?').count() as u32
}

fn estimate_syllables(content: &str) -> u32 {
    let vowels = ['a', 'e', 'i', 'o', 'u', 'A', 'E', 'I', 'O', 'U'];
    let mut syllable_count = 0;

    for word in content.split_whitespace() {
        let word_syllables = count_vowel_groups(word, &vowels);
        syllable_count += word_syllables.max(1); // At least 1 syllable per word
    }

    syllable_count
}

fn count_vowel_groups(word: &str, vowels: &[char]) -> u32 {
    let mut count = 0;
    let mut prev_was_vowel = false;

    for ch in word.chars() {
        let is_vowel = vowels.contains(&ch);
        if is_vowel && !prev_was_vowel {
            count += 1;
        }
        prev_was_vowel = is_vowel;
    }

    count
}

fn extract_functions_from_code_blocks(code_blocks: &[CodeBlockInfo]) -> Vec<String> {
    let mut functions = Vec::new();

    for block in code_blocks {
        if let Some(lang) = &block.language {
            match lang.to_lowercase().as_str() {
                "javascript" | "js" | "typescript" | "ts" => {
                    extract_js_functions(&block.content, &mut functions);
                }
                "python" | "py" => {
                    extract_python_functions(&block.content, &mut functions);
                }
                "rust" | "rs" => {
                    extract_rust_functions(&block.content, &mut functions);
                }
                _ => {}
            }
        }
    }

    functions
}

fn extract_js_functions(content: &str, functions: &mut Vec<String>) {
    let function_regex = Regex::new(r"function\s+(\w+)|const\s+(\w+)\s*=\s*\([^)]*\)\s*=>|(\w+)\s*:\s*function").unwrap();

    for captures in function_regex.captures_iter(content) {
        if let Some(name) = captures.get(1).or_else(|| captures.get(2)).or_else(|| captures.get(3)) {
            functions.push(name.as_str().to_string());
        }
    }
}

fn extract_python_functions(content: &str, functions: &mut Vec<String>) {
    let function_regex = Regex::new(r"def\s+(\w+)").unwrap();

    for captures in function_regex.captures_iter(content) {
        if let Some(name) = captures.get(1) {
            functions.push(name.as_str().to_string());
        }
    }
}

fn extract_rust_functions(content: &str, functions: &mut Vec<String>) {
    let function_regex = Regex::new(r"fn\s+(\w+)").unwrap();

    for captures in function_regex.captures_iter(content) {
        if let Some(name) = captures.get(1) {
            functions.push(name.as_str().to_string());
        }
    }
}

fn extract_classes_from_content(content: &str) -> Vec<String> {
    let class_regex = Regex::new(r"class\s+(\w+)|struct\s+(\w+)|interface\s+(\w+)").unwrap();
    let mut classes = Vec::new();

    for captures in class_regex.captures_iter(content) {
        if let Some(name) = captures.get(1).or_else(|| captures.get(2)).or_else(|| captures.get(3)) {
            classes.push(name.as_str().to_string());
        }
    }

    classes
}

fn extract_imports_from_code_blocks(code_blocks: &[CodeBlockInfo]) -> Vec<String> {
    let mut imports = Vec::new();

    for block in code_blocks {
        if let Some(lang) = &block.language {
            let import_regex = match lang.to_lowercase().as_str() {
                "javascript" | "js" | "typescript" | "ts" => {
                    Regex::new(r"import\s+.*\s+from\s+['\"]([^'\"]+)['\"]").unwrap()
                }
                "python" | "py" => {
                    Regex::new(r"from\s+(\S+)\s+import|import\s+(\S+)").unwrap()
                }
                "rust" | "rs" => {
                    Regex::new(r"use\s+([^;]+)").unwrap()
                }
                _ => continue,
            };

            for captures in import_regex.captures_iter(&block.content) {
                if let Some(import) = captures.get(1).or_else(|| captures.get(2)) {
                    imports.push(import.as_str().to_string());
                }
            }
        }
    }

    imports
}

fn generate_markdown_suggestions(content: &str, metrics: &MarkdownMetrics) -> Vec<String> {
    let mut suggestions = Vec::new();

    // Structure suggestions
    if metrics.headers.is_empty() {
        suggestions.push("Consider adding headers to improve document structure".to_string());
    }

    if metrics.headers.len() > 0 && !metrics.headers.iter().any(|h| h.level == 1) {
        suggestions.push("Add a main title (# Header) to the document".to_string());
    }

    // Content suggestions
    if metrics.total_words > 2000 && metrics.headers.len() < 3 {
        suggestions.
