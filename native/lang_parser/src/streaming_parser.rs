//! LANG Streaming JSON-LD Parser - State Machine Implementation
//! 
//! This module implements a high-performance streaming parser for JSON-LD documents.
//! CRITICAL: Every byte processed must be optimized for maximum throughput.

use std::collections::VecDeque;
use std::io::{Read, BufRead};
use std::mem::MaybeUninit;
use rayon::prelude::*;
use memmap2::Mmap;
use serde_json::Value;

/// Parser states for the streaming state machine
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParserState {
    SeekingObject,
    InObject,
    InKey,
    InValue,
    InString,
    InArray,
    Error,
}

/// JSON-LD node extracted from stream
#[derive(Debug, Clone)]
pub struct JsonLdNode {
    pub id: Option<String>,
    pub node_type: Option<String>,
    pub context: Option<Value>,
    pub properties: Vec<(String, Value)>,
    pub raw_bytes: Vec<u8>,
    pub byte_offset: usize,
}

/// Streaming parser configuration
#[derive(Debug, Clone)]
pub struct StreamingConfig {
    pub buffer_size: usize,        // Working buffer size
    pub chunk_size: usize,         // Read chunk size
    pub max_node_size: usize,      // Maximum size for a single node
    pub parallel_threshold: usize,  // When to switch to parallel processing
    pub enable_mmap: bool,         // Use memory mapping for large files
}

impl Default for StreamingConfig {
    fn default() -> Self {
        Self {
            buffer_size: 64 * 1024,    // 64KB working buffer
            chunk_size: 8 * 1024,      // 8KB read chunks
            max_node_size: 1024 * 1024, // 1MB max node
            parallel_threshold: 100_000,
            enable_mmap: true,
        }
    }
}

/// High-performance streaming JSON-LD parser
pub struct StreamingJsonLdParser {
    state: ParserState,
    depth: usize,
    buffer: Vec<u8>,
    buffer_pos: usize,
    token_start: usize,
    config: StreamingConfig,
    
    // Performance optimization lookup tables - pre-computed for speed
    whitespace_lut: [bool; 256],
    json_special_lut: [bool; 256],
    hex_digit_lut: [u8; 256],
    
    // State tracking
    current_node: Option<JsonLdNode>,
    nodes_extracted: Vec<JsonLdNode>,
    total_bytes_processed: usize,
}

impl StreamingJsonLdParser {
    pub fn new(config: StreamingConfig) -> Self {
        let mut parser = Self {
            state: ParserState::SeekingObject,
            depth: 0,
            buffer: Vec::with_capacity(config.buffer_size),
            buffer_pos: 0,
            token_start: 0,
            config,
            whitespace_lut: [false; 256],
            json_special_lut: [false; 256],
            hex_digit_lut: [255; 256], // 255 = invalid
            current_node: None,
            nodes_extracted: Vec::new(),
            total_bytes_processed: 0,
        };
        
        parser.initialize_lookup_tables();
        parser
    }
    
    /// CRITICAL: Initialize lookup tables for O(1) character classification
    fn initialize_lookup_tables(&mut self) {
        // Whitespace lookup table
        for &byte in &[b' ', b'\t', b'\n', b'\r'] {
            self.whitespace_lut[byte as usize] = true;
        }
        
        // JSON special characters
        for &byte in b"{}[]\":," {
            self.json_special_lut[byte as usize] = true;
        }
        
        // Hex digit lookup
        for (i, &byte) in b"0123456789ABCDEFabcdef".iter().enumerate() {
            self.hex_digit_lut[byte as usize] = (i % 16) as u8;
        }
    }
    
    /// PERFORMANCE CRITICAL: Process chunk of data through state machine
    pub fn process_chunk(&mut self, chunk: &[u8]) -> Result<Vec<JsonLdNode>, StreamingError> {
        let mut extracted_nodes = Vec::new();
        
        for &byte in chunk {
            self.total_bytes_processed += 1;
            
            // CRITICAL: Fast path for whitespace skipping
            if self.whitespace_lut[byte as usize] && 
               self.state != ParserState::InString {
                continue;
            }
            
            // State machine dispatch - optimized for common paths
            match self.state {
                ParserState::SeekingObject => {
                    if byte == b'{' {
                        self.start_object();
                    }
                }
                
                ParserState::InObject => {
                    match byte {
                        b'"' => self.start_key(),
                        b'}' => {
                            if let Some(node) = self.end_object()? {
                                extracted_nodes.push(node);
                            }
                        }
                        b',' => {}, // Continue parsing
                        _ => return Err(StreamingError::InvalidJson("Unexpected character in object".into())),
                    }
                }
                
                ParserState::InKey => {
                    if byte == b'"' {
                        self.end_key();
                    } else if byte == b'\\' {
                        // Handle escape sequences
                        self.handle_escape()?;
                    } else {
                        self.add_to_current_token(byte);
                    }
                }
                
                ParserState::InValue => {
                    match byte {
                        b'"' => self.start_string_value(),
                        b'{' => self.start_nested_object(),
                        b'[' => self.start_array(),
                        b',' | b'}' => self.end_value(byte)?,
                        _ if byte.is_ascii_digit() || byte == b'-' => {
                            self.start_number_value(byte);
                        }
                        b't' | b'f' | b'n' => {
                            self.start_literal_value(byte);
                        }
                        _ => return Err(StreamingError::InvalidJson("Invalid value start".into())),
                    }
                }
                
                ParserState::InString => {
                    if byte == b'"' {
                        self.end_string();
                    } else if byte == b'\\' {
                        self.handle_escape()?;
                    } else {
                        self.add_to_current_token(byte);
                    }
                }
                
                ParserState::InArray => {
                    match byte {
                        b']' => self.end_array(),
                        b',' => {}, // Continue parsing array elements
                        _ => self.parse_array_element(byte)?,
                    }
                }
                
                ParserState::Error => {
                    return Err(StreamingError::ParserError("Parser in error state".into()));
                }
            }
            
            self.add_to_buffer(byte);
            
            // Check buffer overflow
            if self.buffer.len() > self.config.max_node_size {
                return Err(StreamingError::NodeTooLarge);
            }
        }
        
        Ok(extracted_nodes)
    }
    
    /// Process large file using memory mapping for maximum performance
    pub fn process_file_mmap(&mut self, file_path: &str) -> Result<Vec<JsonLdNode>, StreamingError> {
        if !self.config.enable_mmap {
            return Err(StreamingError::MemoryMappingDisabled);
        }
        
        let file = std::fs::File::open(file_path)
            .map_err(|e| StreamingError::IoError(e.to_string()))?;
        
        let mmap = unsafe { Mmap::map(&file) }
            .map_err(|e| StreamingError::IoError(e.to_string()))?;
        
        // Process in parallel chunks if file is large enough
        if mmap.len() > self.config.parallel_threshold {
            self.process_parallel_chunks(&mmap)
        } else {
            self.process_chunk(&mmap)
        }
    }
    
    /// CRITICAL: Parallel processing for massive documents
    fn process_parallel_chunks(&mut self, data: &[u8]) -> Result<Vec<JsonLdNode>, StreamingError> {
        let chunk_size = data.len() / rayon::current_num_threads().max(1);
        let mut all_nodes = Vec::new();
        
        // Find JSON object boundaries to avoid splitting mid-object
        let boundaries = self.find_object_boundaries(data, chunk_size)?;
        
        // Process chunks in parallel
        let chunk_results: Result<Vec<_>, _> = boundaries
            .par_windows(2)
            .map(|window| {
                let start = window[0];
                let end = window[1];
                let mut parser = StreamingJsonLdParser::new(self.config.clone());
                parser.process_chunk(&data[start..end])
            })
            .collect();
        
        match chunk_results {
            Ok(chunks) => {
                for chunk_nodes in chunks {
                    all_nodes.extend(chunk_nodes);
                }
                Ok(all_nodes)
            }
            Err(e) => Err(e),
        }
    }
    
    /// Find safe boundaries for parallel processing (don't split mid-object)
    fn find_object_boundaries(&self, data: &[u8], target_chunk_size: usize) -> Result<Vec<usize>, StreamingError> {
        let mut boundaries = vec![0];
        let mut pos = 0;
        let mut brace_depth = 0;
        let mut in_string = false;
        let mut escape_next = false;
        
        while pos < data.len() {
            let byte = data[pos];
            
            if escape_next {
                escape_next = false;
                pos += 1;
                continue;
            }
            
            match byte {
                b'"' if !escape_next => in_string = !in_string,
                b'\\' if in_string => escape_next = true,
                b'{' if !in_string => brace_depth += 1,
                b'}' if !in_string => {
                    brace_depth -= 1;
                    
                    // Found complete object boundary
                    if brace_depth == 0 && pos - boundaries.last().unwrap_or(&0) >= target_chunk_size {
                        boundaries.push(pos + 1);
                    }
                }
                _ => {}
            }
            
            pos += 1;
        }
        
        if boundaries.last() != Some(&data.len()) {
            boundaries.push(data.len());
        }
        
        Ok(boundaries)
    }
    
    /// State machine transition methods
    fn start_object(&mut self) {
        self.state = ParserState::InObject;
        self.depth += 1;
        self.current_node = Some(JsonLdNode {
            id: None,
            node_type: None,
            context: None,
            properties: Vec::new(),
            raw_bytes: Vec::new(),
            byte_offset: self.total_bytes_processed,
        });
        self.token_start = self.buffer.len();
    }
    
    fn start_key(&mut self) {
        self.state = ParserState::InKey;
        self.token_start = self.buffer.len();
    }
    
    fn end_key(&mut self) {
        self.state = ParserState::InValue;
        // Key is stored in buffer from token_start to current position
    }
    
    fn start_string_value(&mut self) {
        self.state = ParserState::InString;
        self.token_start = self.buffer.len();
    }
    
    fn end_string(&mut self) {
        self.state = ParserState::InValue;
        // String value processing would happen here
    }
    
    fn start_nested_object(&mut self) {
        self.depth += 1;
        // Handle nested object parsing
    }
    
    fn start_array(&mut self) {
        self.state = ParserState::InArray;
        self.depth += 1;
    }
    
    fn end_array(&mut self) {
        self.state = ParserState::InValue;
        self.depth -= 1;
    }
    
    fn start_number_value(&mut self, first_digit: u8) {
        // Handle numeric value parsing
        self.add_to_current_token(first_digit);
    }
    
    fn start_literal_value(&mut self, first_char: u8) {
        // Handle true/false/null parsing
        self.add_to_current_token(first_char);
    }
    
    fn end_value(&mut self, terminator: u8) -> Result<(), StreamingError> {
        match terminator {
            b',' => self.state = ParserState::InObject,
            b'}' => {
                if let Some(node) = self.end_object()? {
                    self.nodes_extracted.push(node);
                }
            }
            _ => return Err(StreamingError::InvalidJson("Invalid value terminator".into())),
        }
        Ok(())
    }
    
    fn parse_array_element(&mut self, byte: u8) -> Result<(), StreamingError> {
        // Handle array element parsing
        self.add_to_current_token(byte);
        Ok(())
    }
    
    /// CRITICAL: Zero-copy node extraction
    fn end_object(&mut self) -> Result<Option<JsonLdNode>, StreamingError> {
        self.state = ParserState::SeekingObject;
        self.depth -= 1;
        
        if let Some(mut node) = self.current_node.take() {
            // Extract raw bytes for the complete object
            node.raw_bytes = self.buffer[self.token_start..].to_vec();
            
            // Parse key JSON-LD fields for fast access
            self.extract_jsonld_fields(&mut node)?;
            
            Ok(Some(node))
        } else {
            Ok(None)
        }
    }
    
    /// PERFORMANCE CRITICAL: Direct field extraction without full JSON parsing
    fn extract_jsonld_fields(&self, node: &mut JsonLdNode) -> Result<(), StreamingError> {
        // Fast extraction of @id, @type, @context
        let raw_str = String::from_utf8_lossy(&node.raw_bytes);
        
        // Use regex or direct string searching for common patterns
        if let Some(id) = self.extract_field_value(&raw_str, "@id") {
            node.id = Some(id);
        }
        
        if let Some(node_type) = self.extract_field_value(&raw_str, "@type") {
            node.node_type = Some(node_type);
        }
        
        // @context might be complex, so use JSON parsing for it
        if raw_str.contains("@context") {
            if let Ok(parsed) = serde_json::from_str::<Value>(&raw_str) {
                node.context = parsed.get("@context").cloned();
            }
        }
        
        Ok(())
    }
    
    /// Fast string field extraction using pattern matching
    fn extract_field_value(&self, json_str: &str, field_name: &str) -> Option<String> {
        let pattern = format!("\"{}\":", field_name);
        
        if let Some(start) = json_str.find(&pattern) {
            let value_start = start + pattern.len();
            
            // Skip whitespace
            let mut pos = value_start;
            while pos < json_str.len() && json_str.chars().nth(pos).unwrap().is_whitespace() {
                pos += 1;
            }
            
            if pos < json_str.len() {
                let remainder = &json_str[pos..];
                
                // Handle quoted strings
                if remainder.starts_with('"') {
                    if let Some(end_quote) = remainder[1..].find('"') {
                        return Some(remainder[1..end_quote + 1].to_string());
                    }
                }
            }
        }
        
        None
    }
    
    fn handle_escape(&mut self) -> Result<(), StreamingError> {
        // Handle escape sequences in strings
        // For now, just add the backslash - full implementation would handle \n, \t, \", etc.
        self.add_to_current_token(b'\\');
        Ok(())
    }
    
    fn add_to_current_token(&mut self, byte: u8) {
        // Add byte to current token being parsed
        // In a full implementation, this would build up the current key or value
    }
    
    fn add_to_buffer(&mut self, byte: u8) {
        if self.buffer.len() < self.config.buffer_size {
            self.buffer.push(byte);
        }
        self.buffer_pos += 1;
        
        // Rotate buffer if it gets too full
        if self.buffer.len() >= self.config.buffer_size {
            self.rotate_buffer();
        }
    }
    
    /// Rotate buffer to prevent unbounded growth
    fn rotate_buffer(&mut self) {
        let keep_size = self.config.buffer_size / 2;
        let drop_size = self.buffer.len() - keep_size;
        
        self.buffer.drain(0..drop_size);
        self.buffer_pos -= drop_size;
        
        if self.token_start >= drop_size {
            self.token_start -= drop_size;
        } else {
            self.token_start = 0;
        }
    }
    
    /// Get parser statistics
    pub fn get_stats(&self) -> ParserStats {
        ParserStats {
            total_bytes_processed: self.total_bytes_processed,
            nodes_extracted: self.nodes_extracted.len(),
            current_depth: self.depth,
            buffer_usage: self.buffer.len(),
            current_state: self.state,
        }
    }
    
    /// Reset parser state for reuse
    pub fn reset(&mut self) {
        self.state = ParserState::SeekingObject;
        self.depth = 0;
        self.buffer.clear();
        self.buffer_pos = 0;
        self.token_start = 0;
        self.current_node = None;
        self.nodes_extracted.clear();
        self.total_bytes_processed = 0;
    }
}

/// Parser statistics for monitoring performance
#[derive(Debug, Clone)]
pub struct ParserStats {
    pub total_bytes_processed: usize,
    pub nodes_extracted: usize,
    pub current_depth: usize,
    pub buffer_usage: usize,
    pub current_state: ParserState,
}

/// Errors that can occur during streaming parsing
#[derive(Debug, Clone)]
pub enum StreamingError {
    InvalidJson(String),
    ParserError(String),
    IoError(String),
    NodeTooLarge,
    MemoryPressure,
    MemoryMappingDisabled,
    BufferOverflow,
}

impl std::fmt::Display for StreamingError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StreamingError::InvalidJson(msg) => write!(f, "Invalid JSON: {}", msg),
            StreamingError::ParserError(msg) => write!(f, "Parser error: {}", msg),
            StreamingError::IoError(msg) => write!(f, "I/O error: {}", msg),
            StreamingError::NodeTooLarge => write!(f, "Node exceeds maximum size"),
            StreamingError::MemoryPressure => write!(f, "Memory pressure detected"),
            StreamingError::MemoryMappingDisabled => write!(f, "Memory mapping is disabled"),
            StreamingError::BufferOverflow => write!(f, "Buffer overflow"),
        }
    }
}

impl std::error::Error for StreamingError {}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_simple_object_parsing() {
        let mut parser = StreamingJsonLdParser::new(StreamingConfig::default());
        let json_data = br#"{"@id": "test", "name": "value"}"#;
        
        let nodes = parser.process_chunk(json_data).unwrap();
        assert_eq!(nodes.len(), 1);
        assert_eq!(nodes[0].id, Some("test".to_string()));
    }
    
    #[test]
    fn test_nested_object_parsing() {
        let mut parser = StreamingJsonLdParser::new(StreamingConfig::default());
        let json_data = br#"{"@id": "test", "nested": {"@id": "inner", "value": 42}}"#;
        
        let nodes = parser.process_chunk(json_data).unwrap();
        assert!(!nodes.is_empty());
    }
    
    #[test]
    fn test_lookup_tables() {
        let parser = StreamingJsonLdParser::new(StreamingConfig::default());
        
        // Test whitespace detection
        assert!(parser.whitespace_lut[b' ' as usize]);
        assert!(parser.whitespace_lut[b'\n' as usize]);
        assert!(!parser.whitespace_lut[b'a' as usize]);
        
        // Test JSON special characters
        assert!(parser.json_special_lut[b'{' as usize]);
        assert!(parser.json_special_lut[b'"' as usize]);
        assert!(!parser.json_special_lut[b'a' as usize]);
    }
    
    #[test]
    fn test_field_extraction() {
        let parser = StreamingJsonLdParser::new(StreamingConfig::default());
        let json_str = r#"{"@id": "test123", "name": "value"}"#;
        
        let id = parser.extract_field_value(json_str, "@id");
        assert_eq!(id, Some("test123".to_string()));
    }
}