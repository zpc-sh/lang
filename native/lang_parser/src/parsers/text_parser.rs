use super::{ParseResult, ParseMetadata, Parser};
use std::collections::HashMap;
use std::time::Instant;

pub struct TextParser;

impl TextParser {
    pub fn new() -> Self {
        TextParser
    }
}

impl Parser for TextParser {
    fn parse(&self, content: &str) -> ParseResult {
        let start = Instant::now();
        
        if content.is_empty() {
            return ParseResult::error("Empty content".to_string());
        }
        
        let lines: Vec<&str> = content.lines().collect();
        let line_count = lines.len();
        let word_count = content.split_whitespace().count();
        let char_count = content.chars().count();
        
        let mut metadata = ParseMetadata {
            format: "text".to_string(),
            size_bytes: content.len(),
            parse_time_ms: start.elapsed().as_millis() as u64,
            features: HashMap::new(),
        };
        
        metadata.features.insert("line_count".to_string(), line_count.to_string());
        metadata.features.insert("word_count".to_string(), word_count.to_string());
        metadata.features.insert("char_count".to_string(), char_count.to_string());
        
        // Basic text analysis
        let avg_line_length = if line_count > 0 {
            char_count / line_count
        } else {
            0
        };
        
        metadata.features.insert("avg_line_length".to_string(), avg_line_length.to_string());
        
        // Check for common patterns
        let has_urls = content.contains("http://") || content.contains("https://");
        let has_emails = content.contains('@') && content.contains('.');
        
        metadata.features.insert("has_urls".to_string(), has_urls.to_string());
        metadata.features.insert("has_emails".to_string(), has_emails.to_string());
        
        ParseResult::success(content.to_string(), metadata)
    }
    
    fn supports_format(&self, format: &str) -> bool {
        matches!(format.to_lowercase().as_str(), "txt" | "text" | "plain")
    }
    
    fn get_format_name(&self) -> &str {
        "text"
    }
}