use super::{ParseResult, ParseMetadata, Parser};
use std::collections::HashMap;
use std::time::Instant;
use serde_json::Value;

pub struct JsonParser;

impl JsonParser {
    pub fn new() -> Self {
        JsonParser
    }
}

impl Parser for JsonParser {
    fn parse(&self, content: &str) -> ParseResult {
        let start = Instant::now();
        
        if content.is_empty() {
            return ParseResult::error("Empty JSON content".to_string());
        }
        
        // Try to parse as JSON
        match serde_json::from_str::<Value>(content) {
            Ok(json_value) => {
                let mut metadata = ParseMetadata {
                    format: "json".to_string(),
                    size_bytes: content.len(),
                    parse_time_ms: start.elapsed().as_millis() as u64,
                    features: HashMap::new(),
                };
                
                // Analyze JSON structure
                let (object_count, array_count, null_count, bool_count, number_count, string_count) = 
                    count_json_types(&json_value);
                
                metadata.features.insert("object_count".to_string(), object_count.to_string());
                metadata.features.insert("array_count".to_string(), array_count.to_string());
                metadata.features.insert("null_count".to_string(), null_count.to_string());
                metadata.features.insert("bool_count".to_string(), bool_count.to_string());
                metadata.features.insert("number_count".to_string(), number_count.to_string());
                metadata.features.insert("string_count".to_string(), string_count.to_string());
                
                // Check for special JSON-LD properties
                if let Value::Object(map) = &json_value {
                    let is_jsonld = map.contains_key("@context") || 
                                   map.contains_key("@id") || 
                                   map.contains_key("@type");
                    metadata.features.insert("is_jsonld".to_string(), is_jsonld.to_string());
                    
                    // Count top-level keys
                    metadata.features.insert("top_level_keys".to_string(), map.len().to_string());
                }
                
                // Calculate depth
                let depth = calculate_json_depth(&json_value, 0);
                metadata.features.insert("max_depth".to_string(), depth.to_string());
                
                ParseResult::success(content.to_string(), metadata)
            }
            Err(e) => {
                ParseResult::error(format!("JSON parsing error: {}", e))
            }
        }
    }
    
    fn supports_format(&self, format: &str) -> bool {
        matches!(format.to_lowercase().as_str(), "json" | "jsonld" | "json-ld")
    }
    
    fn get_format_name(&self) -> &str {
        "json"
    }
}

fn count_json_types(value: &Value) -> (usize, usize, usize, usize, usize, usize) {
    let mut object_count = 0;
    let mut array_count = 0;
    let mut null_count = 0;
    let mut bool_count = 0;
    let mut number_count = 0;
    let mut string_count = 0;
    
    match value {
        Value::Object(map) => {
            object_count += 1;
            for (_key, val) in map {
                let (o, a, n, b, num, s) = count_json_types(val);
                object_count += o;
                array_count += a;
                null_count += n;
                bool_count += b;
                number_count += num;
                string_count += s;
            }
        }
        Value::Array(arr) => {
            array_count += 1;
            for val in arr {
                let (o, a, n, b, num, s) = count_json_types(val);
                object_count += o;
                array_count += a;
                null_count += n;
                bool_count += b;
                number_count += num;
                string_count += s;
            }
        }
        Value::Null => null_count += 1,
        Value::Bool(_) => bool_count += 1,
        Value::Number(_) => number_count += 1,
        Value::String(_) => string_count += 1,
    }
    
    (object_count, array_count, null_count, bool_count, number_count, string_count)
}

fn calculate_json_depth(value: &Value, current_depth: usize) -> usize {
    match value {
        Value::Object(map) => {
            let mut max_depth = current_depth;
            for (_key, val) in map {
                let depth = calculate_json_depth(val, current_depth + 1);
                if depth > max_depth {
                    max_depth = depth;
                }
            }
            max_depth
        }
        Value::Array(arr) => {
            let mut max_depth = current_depth;
            for val in arr {
                let depth = calculate_json_depth(val, current_depth + 1);
                if depth > max_depth {
                    max_depth = depth;
                }
            }
            max_depth
        }
        _ => current_depth
    }
}