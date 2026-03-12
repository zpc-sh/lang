use rustler::{Binary, Env, NifResult, Term, Encoder, Atom};
use pulldown_cmark::{Parser, Options, Event, Tag, CodeBlockKind, HeadingLevel};
use std::collections::HashMap;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        nil,
    }
}

// Elixir-compatible map structure
type ElixirMap = HashMap<String, Term<'static>>;

#[rustler::nif]
fn parse_markdown<'a>(env: Env<'a>, content: String, _options: Vec<(String, String)>) -> Term<'a> {
    let result = parse_markdown_content(env, &content);
    (atoms::ok(), result).encode(env)
}

#[rustler::nif]
fn parse_markdown_binary<'a>(env: Env<'a>, binary: Binary, _options: Vec<(String, String)>) -> Term<'a> {
    let content = match std::str::from_utf8(binary.as_slice()) {
        Ok(s) => s,
        Err(_) => return (atoms::error(), "Invalid UTF-8").encode(env),
    };
    
    let result = parse_markdown_content(env, content);
    (atoms::ok(), result).encode(env)
}

#[rustler::nif]
fn parse_batch_parallel<'a>(env: Env<'a>, documents: Vec<String>, _options: Vec<(String, String)>) -> Term<'a> {
    let results: Vec<Term> = documents.iter()
        .map(|doc| parse_markdown_content(env, doc))
        .collect();
    
    (atoms::ok(), results).encode(env)
}

#[rustler::nif]
fn word_count_simd<'a>(env: Env<'a>, content: String) -> Term<'a> {
    let count = content.split_whitespace().count();
    (atoms::ok(), count).encode(env)
}

#[rustler::nif]
fn extract_links_simd<'a>(env: Env<'a>, content: String) -> Term<'a> {
    let links = extract_links(env, &content);
    (atoms::ok(), links).encode(env)
}

#[rustler::nif]
fn extract_headings_simd<'a>(env: Env<'a>, content: String) -> Term<'a> {
    let headings = extract_headings(env, &content);
    (atoms::ok(), headings).encode(env)
}

#[rustler::nif]
fn extract_code_blocks_simd<'a>(env: Env<'a>, content: String) -> Term<'a> {
    let code_blocks = extract_code_blocks(env, &content);
    (atoms::ok(), code_blocks).encode(env)
}

#[rustler::nif]
fn extract_tasks_simd<'a>(env: Env<'a>, content: String) -> Term<'a> {
    let tasks = extract_tasks(env, &content);
    (atoms::ok(), tasks).encode(env)
}

#[rustler::nif]
fn get_performance_stats<'a>(env: Env<'a>) -> Term<'a> {
    let mut stats = HashMap::new();
    stats.insert("simd_operations".to_string(), 0i64.encode(env));
    stats.insert("cache_hit_rate".to_string(), 0.0f64.encode(env));
    stats.insert("memory_pool_usage".to_string(), 0i64.encode(env));
    stats.insert("pattern_cache_size".to_string(), 0i64.encode(env));
    
    (atoms::ok(), stats).encode(env)
}

#[rustler::nif]
fn reset_performance_stats() -> Atom {
    atoms::ok()
}

#[rustler::nif]
fn clear_pattern_cache() -> Atom {
    atoms::ok()
}

// Core parsing function
fn parse_markdown_content<'a>(env: Env<'a>, content: &str) -> Term<'a> {
    let start_time = std::time::Instant::now();
    
    let links = extract_links(env, content);
    let headings = extract_headings(env, content);
    let code_blocks = extract_code_blocks(env, content);
    let tasks = extract_tasks(env, content);
    let word_count = content.split_whitespace().count();
    
    let processing_time = start_time.elapsed().as_micros() as u64;
    
    let mut result = HashMap::new();
    result.insert("headings".to_string(), headings);
    result.insert("links".to_string(), links);
    result.insert("code_blocks".to_string(), code_blocks);
    result.insert("tasks".to_string(), tasks);
    result.insert("word_count".to_string(), word_count.encode(env));
    result.insert("processing_time_us".to_string(), processing_time.encode(env));
    
    result.encode(env)
}

fn extract_links<'a>(env: Env<'a>, content: &str) -> Term<'a> {
    let mut links = Vec::new();
    let mut line = 1usize;
    
    let mut options = Options::empty();
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TABLES);
    options.insert(Options::ENABLE_FOOTNOTES);
    
    let parser = Parser::new_ext(content, options);
    
    let mut link_text = String::new();
    let mut in_link = false;
    
    for event in parser {
        match event {
            Event::Start(Tag::Link(_, dest_url, title)) => {
                in_link = true;
                link_text.clear();
                if !title.is_empty() {
                    link_text.push_str(&title);
                }
                
                if !dest_url.is_empty() {
                    let mut link_map = HashMap::new();
                    link_map.insert("text".to_string(), link_text.encode(env));
                    link_map.insert("url".to_string(), dest_url.to_string().encode(env));
                    link_map.insert("line".to_string(), line.encode(env));
                    
                    links.push(link_map.encode(env));
                }
                in_link = false;
            }
            Event::Text(text) => {
                if in_link {
                    link_text.push_str(&text);
                }
                // Count newlines
                line += text.chars().filter(|&c| c == '\n').count();
            }
            Event::SoftBreak | Event::HardBreak => {
                line += 1;
            }
            _ => {}
        }
    }
    
    links.encode(env)
}

fn extract_headings<'a>(env: Env<'a>, content: &str) -> Term<'a> {
    let mut headings = Vec::new();
    let mut current_line = 1usize;
    let mut in_heading = false;
    let mut heading_level = 1u32;
    let mut heading_text = String::new();
    
    let mut options = Options::empty();
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TABLES);
    options.insert(Options::ENABLE_FOOTNOTES);
    
    let parser = Parser::new_ext(content, options);
    
    for event in parser {
        match event {
            Event::Start(Tag::Heading(level, _, _)) => {
                in_heading = true;
                heading_level = match level {
                    HeadingLevel::H1 => 1,
                    HeadingLevel::H2 => 2,
                    HeadingLevel::H3 => 3,
                    HeadingLevel::H4 => 4,
                    HeadingLevel::H5 => 5,
                    HeadingLevel::H6 => 6,
                };
                heading_text.clear();
            }
            Event::End(Tag::Heading(_, _, _)) => {
                if in_heading {
                    let mut heading_map = HashMap::new();
                    heading_map.insert("level".to_string(), heading_level.encode(env));
                    heading_map.insert("text".to_string(), heading_text.clone().encode(env));
                    heading_map.insert("line".to_string(), current_line.encode(env));
                    
                    headings.push(heading_map.encode(env));
                    in_heading = false;
                }
            }
            Event::Text(text) => {
                if in_heading {
                    heading_text.push_str(&text);
                }
                // Count newlines
                current_line += text.chars().filter(|&c| c == '\n').count();
            }
            Event::SoftBreak | Event::HardBreak => {
                current_line += 1;
            }
            _ => {}
        }
    }
    
    headings.encode(env)
}

fn extract_code_blocks<'a>(env: Env<'a>, content: &str) -> Term<'a> {
    let mut code_blocks = Vec::new();
    let mut current_line = 1usize;
    let mut in_code_block = false;
    let mut current_code = String::new();
    let mut current_language: Option<String> = None;
    let mut code_start_line = 1usize;
    
    let mut options = Options::empty();
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TABLES);
    options.insert(Options::ENABLE_FOOTNOTES);
    
    let parser = Parser::new_ext(content, options);
    
    for event in parser {
        match event {
            Event::Start(Tag::CodeBlock(kind)) => {
                in_code_block = true;
                current_language = match kind {
                    CodeBlockKind::Fenced(lang) => {
                        if lang.is_empty() {
                            None
                        } else {
                            Some(lang.to_string())
                        }
                    }
                    CodeBlockKind::Indented => None,
                };
                code_start_line = current_line;
                current_code.clear();
            }
            Event::End(Tag::CodeBlock(_)) => {
                if in_code_block {
                    let mut code_map = HashMap::new();
                    code_map.insert("language".to_string(), 
                        match &current_language {
                            Some(lang) => lang.clone().encode(env),
                            None => atoms::nil().encode(env),
                        });
                    code_map.insert("content".to_string(), current_code.clone().encode(env));
                    code_map.insert("line".to_string(), code_start_line.encode(env));
                    
                    code_blocks.push(code_map.encode(env));
                    in_code_block = false;
                }
            }
            Event::Text(text) => {
                if in_code_block {
                    current_code.push_str(&text);
                }
                // Count newlines
                current_line += text.chars().filter(|&c| c == '\n').count();
            }
            Event::SoftBreak | Event::HardBreak => {
                if in_code_block {
                    current_code.push('\n');
                }
                current_line += 1;
            }
            _ => {}
        }
    }
    
    code_blocks.encode(env)
}

fn extract_tasks<'a>(env: Env<'a>, content: &str) -> Term<'a> {
    let mut tasks = Vec::new();
    let mut line_num = 1usize;
    
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("- [ ]") || trimmed.starts_with("* [ ]") {
            let mut task_map = HashMap::new();
            task_map.insert("completed".to_string(), false.encode(env));
            task_map.insert("text".to_string(), trimmed[5..].trim().to_string().encode(env));
            task_map.insert("line".to_string(), line_num.encode(env));
            
            tasks.push(task_map.encode(env));
        } else if trimmed.starts_with("- [x]") || trimmed.starts_with("* [x]") {
            let mut task_map = HashMap::new();
            task_map.insert("completed".to_string(), true.encode(env));
            task_map.insert("text".to_string(), trimmed[5..].trim().to_string().encode(env));
            task_map.insert("line".to_string(), line_num.encode(env));
            
            tasks.push(task_map.encode(env));
        }
        line_num += 1;
    }
    
    tasks.encode(env)
}

rustler::init!("Elixir.MarkdownLd.Native");