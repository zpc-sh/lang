// native/lang_parser/src/parsers/mod.rs - Parser module definitions

pub mod text_parser;
pub mod json_parser;
pub mod markdown_parser;

pub use text_parser::*;
pub use json_parser::*;
pub use markdown_parser::*;

use serde::{Serialize, Deserialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParseResult {
    pub success: bool,
    pub content: String,
    pub metadata: ParseMetadata,
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParseMetadata {
    pub format: String,
    pub size_bytes: usize,
    pub parse_time_ms: u64,
    pub features: HashMap<String, String>,
}

pub trait Parser {
    fn parse(&self, content: &str) -> ParseResult;
    fn supports_format(&self, format: &str) -> bool;
    fn get_format_name(&self) -> &str;
}

impl Default for ParseMetadata {
    fn default() -> Self {
        Self {
            format: "unknown".to_string(),
            size_bytes: 0,
            parse_time_ms: 0,
            features: HashMap::new(),
        }
    }
}

impl ParseResult {
    pub fn success(content: String, metadata: ParseMetadata) -> Self {
        Self {
            success: true,
            content,
            metadata,
            errors: Vec::new(),
            warnings: Vec::new(),
        }
    }
    
    pub fn error(error: String) -> Self {
        Self {
            success: false,
            content: String::new(),
            metadata: ParseMetadata::default(),
            errors: vec![error],
            warnings: Vec::new(),
        }
    }
}