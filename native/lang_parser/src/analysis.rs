// native/lang_parser/src/analysis.rs - Text analysis module

use crate::parsers::*;
use serde::{Serialize, Deserialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisResult {
    pub complexity: f64,
    pub readability: f64,
    pub style_score: f64,
    pub metrics: HashMap<String, f64>,
    pub suggestions: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextMetrics {
    pub word_count: usize,
    pub sentence_count: usize,
    pub paragraph_count: usize,
    pub avg_words_per_sentence: f64,
    pub avg_sentences_per_paragraph: f64,
    pub lexical_diversity: f64,
}

pub fn analyze_text_structure(content: &str) -> TextMetrics {
    let words: Vec<&str> = content.split_whitespace().collect();
    let sentences: Vec<&str> = content.split(&['.', '!', '?'][..]).collect();
    let paragraphs: Vec<&str> = content.split("\n\n").collect();
    
    let word_count = words.len();
    let sentence_count = sentences.iter().filter(|s| !s.trim().is_empty()).count();
    let paragraph_count = paragraphs.iter().filter(|p| !p.trim().is_empty()).count();
    
    let avg_words_per_sentence = if sentence_count > 0 {
        word_count as f64 / sentence_count as f64
    } else {
        0.0
    };
    
    let avg_sentences_per_paragraph = if paragraph_count > 0 {
        sentence_count as f64 / paragraph_count as f64
    } else {
        0.0
    };
    
    // Calculate lexical diversity (unique words / total words)
    let unique_words: std::collections::HashSet<&str> = words.iter().cloned().collect();
    let lexical_diversity = if word_count > 0 {
        unique_words.len() as f64 / word_count as f64
    } else {
        0.0
    };
    
    TextMetrics {
        word_count,
        sentence_count,
        paragraph_count,
        avg_words_per_sentence,
        avg_sentences_per_paragraph,
        lexical_diversity,
    }
}

pub fn calculate_complexity_score(content: &str) -> f64 {
    let metrics = analyze_text_structure(content);
    
    // Simple complexity scoring based on various factors
    let sentence_complexity = if metrics.avg_words_per_sentence > 20.0 {
        0.8
    } else if metrics.avg_words_per_sentence > 15.0 {
        0.6
    } else if metrics.avg_words_per_sentence > 10.0 {
        0.4
    } else {
        0.2
    };
    
    let lexical_complexity = metrics.lexical_diversity;
    
    // Weight the different complexity factors
    (sentence_complexity * 0.6) + (lexical_complexity * 0.4)
}

pub fn calculate_readability_score(content: &str) -> f64 {
    let metrics = analyze_text_structure(content);
    
    // Simplified Flesch Reading Ease approximation
    // Higher scores = easier to read
    let avg_sentence_length = metrics.avg_words_per_sentence;
    let syllable_estimate = estimate_syllables(content);
    
    let score = 206.835 - (1.015 * avg_sentence_length) - (84.6 * syllable_estimate);
    
    // Normalize to 0-1 range
    (score / 100.0).max(0.0).min(1.0)
}

fn estimate_syllables(content: &str) -> f64 {
    let words: Vec<&str> = content.split_whitespace().collect();
    if words.is_empty() {
        return 0.0;
    }
    
    let total_syllables: usize = words.iter()
        .map(|word| count_syllables(word))
        .sum();
    
    total_syllables as f64 / words.len() as f64
}

fn count_syllables(word: &str) -> usize {
    let vowels = "aeiouAEIOU";
    let mut syllable_count: usize = 0;
    let mut prev_was_vowel = false;
    
    for ch in word.chars() {
        let is_vowel = vowels.contains(ch);
        if is_vowel && !prev_was_vowel {
            syllable_count += 1;
        }
        prev_was_vowel = is_vowel;
    }
    
    // Handle silent 'e'
    if word.ends_with('e') || word.ends_with('E') {
        syllable_count = syllable_count.saturating_sub(1);
    }
    
    // Every word has at least one syllable
    syllable_count.max(1)
}

pub fn analyze_full_text(content: &str) -> AnalysisResult {
    let metrics = analyze_text_structure(content);
    let complexity = calculate_complexity_score(content);
    let readability = calculate_readability_score(content);
    
    let mut metric_map = HashMap::new();
    metric_map.insert("word_count".to_string(), metrics.word_count as f64);
    metric_map.insert("sentence_count".to_string(), metrics.sentence_count as f64);
    metric_map.insert("paragraph_count".to_string(), metrics.paragraph_count as f64);
    metric_map.insert("avg_words_per_sentence".to_string(), metrics.avg_words_per_sentence);
    metric_map.insert("lexical_diversity".to_string(), metrics.lexical_diversity);
    
    let mut suggestions = Vec::new();
    
    if metrics.avg_words_per_sentence > 25.0 {
        suggestions.push("Consider breaking up long sentences for better readability".to_string());
    }
    
    if metrics.lexical_diversity < 0.3 {
        suggestions.push("Try using more varied vocabulary to improve engagement".to_string());
    }
    
    if readability < 0.4 {
        suggestions.push("Text may be difficult to read - consider simplifying language".to_string());
    }
    
    AnalysisResult {
        complexity,
        readability,
        style_score: (complexity + readability) / 2.0,
        metrics: metric_map,
        suggestions,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_syllable_counting() {
        assert_eq!(count_syllables("hello"), 2);
        assert_eq!(count_syllables("world"), 1);
        assert_eq!(count_syllables("beautiful"), 3);
        assert_eq!(count_syllables("a"), 1);
    }
    
    #[test]
    fn test_text_analysis() {
        let text = "Hello world. This is a test sentence. How are you doing today?";
        let result = analyze_full_text(text);
        
        assert!(result.complexity > 0.0);
        assert!(result.readability > 0.0);
        assert!(result.style_score > 0.0);
        assert!(!result.metrics.is_empty());
    }
}