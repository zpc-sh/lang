use super::{ParseResult, ParseMetadata, Parser};
use std::collections::HashMap;
use std::time::Instant;
use pulldown_cmark::{Parser as CmarkParser, Event, Tag, HeadingLevel};

pub struct MarkdownParser;

impl MarkdownParser {
    pub fn new() -> Self {
        MarkdownParser
    }
}

impl Parser for MarkdownParser {
    fn parse(&self, content: &str) -> ParseResult {
        let start = Instant::now();
        
        if content.is_empty() {
            return ParseResult::error("Empty markdown content".to_string());
        }
        
        let parser = CmarkParser::new(content);
        
        let mut heading_count = 0;
        let mut link_count = 0;
        let mut code_block_count = 0;
        let mut list_count = 0;
        let mut paragraph_count = 0;
        let mut image_count = 0;
        let mut emphasis_count = 0;
        let mut strong_count = 0;
        let mut heading_levels = HashMap::new();
        
        for event in parser {
            match event {
                Event::Start(tag) => {
                    match tag {
                        Tag::Heading(level, _, _) => {
                            heading_count += 1;
                            let level_num = match level {
                                HeadingLevel::H1 => 1,
                                HeadingLevel::H2 => 2,
                                HeadingLevel::H3 => 3,
                                HeadingLevel::H4 => 4,
                                HeadingLevel::H5 => 5,
                                HeadingLevel::H6 => 6,
                            };
                            *heading_levels.entry(level_num).or_insert(0) += 1;
                        }
                        Tag::Link(_, _, _) => link_count += 1,
                        Tag::Image(_, _, _) => image_count += 1,
                        Tag::CodeBlock(_) => code_block_count += 1,
                        Tag::List(_) => list_count += 1,
                        Tag::Paragraph => paragraph_count += 1,
                        Tag::Emphasis => emphasis_count += 1,
                        Tag::Strong => strong_count += 1,
                        _ => {}
                    }
                }
                _ => {}
            }
        }
        
        let mut metadata = ParseMetadata {
            format: "markdown".to_string(),
            size_bytes: content.len(),
            parse_time_ms: start.elapsed().as_millis() as u64,
            features: HashMap::new(),
        };
        
        // Add counts to metadata
        metadata.features.insert("heading_count".to_string(), heading_count.to_string());
        metadata.features.insert("link_count".to_string(), link_count.to_string());
        metadata.features.insert("code_block_count".to_string(), code_block_count.to_string());
        metadata.features.insert("list_count".to_string(), list_count.to_string());
        metadata.features.insert("paragraph_count".to_string(), paragraph_count.to_string());
        metadata.features.insert("image_count".to_string(), image_count.to_string());
        metadata.features.insert("emphasis_count".to_string(), emphasis_count.to_string());
        metadata.features.insert("strong_count".to_string(), strong_count.to_string());
        
        // Add heading level distribution
        for (level, count) in heading_levels {
            metadata.features.insert(format!("h{}_count", level), count.to_string());
        }
        
        // Calculate line and word counts
        let line_count = content.lines().count();
        let word_count = content.split_whitespace().count();
        
        metadata.features.insert("line_count".to_string(), line_count.to_string());
        metadata.features.insert("word_count".to_string(), word_count.to_string());
        
        // Check for frontmatter
        let has_frontmatter = content.starts_with("---\n");
        metadata.features.insert("has_frontmatter".to_string(), has_frontmatter.to_string());
        
        ParseResult::success(content.to_string(), metadata)
    }
    
    fn supports_format(&self, format: &str) -> bool {
        matches!(format.to_lowercase().as_str(), "markdown" | "md" | "mkd" | "mdwn" | "mdown" | "mdtxt" | "mdtext")
    }
    
    fn get_format_name(&self) -> &str {
        "markdown"
    }
}