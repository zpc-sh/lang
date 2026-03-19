// native/lang_parser/src/stylometrics.rs - Stylometric analysis module

use serde::{Serialize, Deserialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StyleProfile {
    pub avg_sentence_length: f64,
    pub vocabulary_richness: f64,
    pub punctuation_frequency: HashMap<char, f64>,
    pub function_word_ratio: f64,
    pub sentence_length_variance: f64,
    pub lexical_density: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StyleComparison {
    pub similarity_score: f64,
    pub differences: Vec<String>,
    pub confidence: f64,
}

pub fn analyze_writing_style(content: &str) -> StyleProfile {
    let sentences = extract_sentences(content);
    let words = extract_words(content);
    let punctuation = count_punctuation(content);
    
    let avg_sentence_length = if sentences.is_empty() {
        0.0
    } else {
        words.len() as f64 / sentences.len() as f64
    };
    
    let vocabulary_richness = calculate_vocabulary_richness(&words);
    let function_word_ratio = calculate_function_word_ratio(&words);
    let sentence_length_variance = calculate_sentence_length_variance(&sentences);
    let lexical_density = calculate_lexical_density(&words);
    
    let total_chars = content.len() as f64;
    let punctuation_frequency: HashMap<char, f64> = punctuation.iter()
        .map(|(&ch, &count)| (ch, count as f64 / total_chars))
        .collect();
    
    StyleProfile {
        avg_sentence_length,
        vocabulary_richness,
        punctuation_frequency,
        function_word_ratio,
        sentence_length_variance,
        lexical_density,
    }
}

pub fn compare_styles(profile1: &StyleProfile, profile2: &StyleProfile) -> StyleComparison {
    let mut similarity_scores = Vec::new();
    let mut differences = Vec::new();
    
    // Compare sentence length
    let sentence_length_diff = (profile1.avg_sentence_length - profile2.avg_sentence_length).abs();
    let sentence_length_similarity = 1.0 - (sentence_length_diff / 30.0).min(1.0);
    similarity_scores.push(sentence_length_similarity);
    
    if sentence_length_diff > 5.0 {
        differences.push(format!("Significant difference in average sentence length: {:.1} vs {:.1}", 
            profile1.avg_sentence_length, profile2.avg_sentence_length));
    }
    
    // Compare vocabulary richness
    let vocab_diff = (profile1.vocabulary_richness - profile2.vocabulary_richness).abs();
    let vocab_similarity = 1.0 - vocab_diff;
    similarity_scores.push(vocab_similarity);
    
    if vocab_diff > 0.1 {
        differences.push(format!("Different vocabulary richness: {:.2} vs {:.2}", 
            profile1.vocabulary_richness, profile2.vocabulary_richness));
    }
    
    // Compare function word ratio
    let function_diff = (profile1.function_word_ratio - profile2.function_word_ratio).abs();
    let function_similarity = 1.0 - function_diff;
    similarity_scores.push(function_similarity);
    
    if function_diff > 0.05 {
        differences.push(format!("Different function word usage: {:.2} vs {:.2}", 
            profile1.function_word_ratio, profile2.function_word_ratio));
    }
    
    // Compare punctuation usage
    let punct_similarity = compare_punctuation(&profile1.punctuation_frequency, &profile2.punctuation_frequency);
    similarity_scores.push(punct_similarity);
    
    let overall_similarity = similarity_scores.iter().sum::<f64>() / similarity_scores.len() as f64;
    let confidence = calculate_confidence(&similarity_scores);
    
    StyleComparison {
        similarity_score: overall_similarity,
        differences,
        confidence,
    }
}

fn extract_sentences(content: &str) -> Vec<String> {
    content.split(&['.', '!', '?'][..])
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

fn extract_words(content: &str) -> Vec<String> {
    content.split_whitespace()
        .map(|word| word.chars().filter(|c| c.is_alphabetic()).collect::<String>().to_lowercase())
        .filter(|word| !word.is_empty())
        .collect()
}

fn count_punctuation(content: &str) -> HashMap<char, usize> {
    let mut counts = HashMap::new();
    for ch in content.chars() {
        if ch.is_ascii_punctuation() {
            *counts.entry(ch).or_insert(0) += 1;
        }
    }
    counts
}

fn calculate_vocabulary_richness(words: &[String]) -> f64 {
    if words.is_empty() {
        return 0.0;
    }
    
    let unique_words: std::collections::HashSet<&String> = words.iter().collect();
    unique_words.len() as f64 / words.len() as f64
}

fn calculate_function_word_ratio(words: &[String]) -> f64 {
    if words.is_empty() {
        return 0.0;
    }
    
    let function_words = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", 
        "of", "with", "by", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could", "should",
        "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them",
        "this", "that", "these", "those", "what", "which", "who", "when", "where", "why", "how"
    ];
    
    let function_word_count = words.iter()
        .filter(|word| function_words.contains(&word.as_str()))
        .count();
    
    function_word_count as f64 / words.len() as f64
}

fn calculate_sentence_length_variance(sentences: &[String]) -> f64 {
    if sentences.len() < 2 {
        return 0.0;
    }
    
    let lengths: Vec<f64> = sentences.iter()
        .map(|s| s.split_whitespace().count() as f64)
        .collect();
    
    let mean = lengths.iter().sum::<f64>() / lengths.len() as f64;
    let variance = lengths.iter()
        .map(|&len| (len - mean).powi(2))
        .sum::<f64>() / lengths.len() as f64;
    
    variance.sqrt()
}

fn calculate_lexical_density(words: &[String]) -> f64 {
    if words.is_empty() {
        return 0.0;
    }
    
    let function_words = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", 
        "of", "with", "by", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could", "should"
    ];
    
    let content_words = words.iter()
        .filter(|word| !function_words.contains(&word.as_str()))
        .count();
    
    content_words as f64 / words.len() as f64
}

fn compare_punctuation(freq1: &HashMap<char, f64>, freq2: &HashMap<char, f64>) -> f64 {
    let all_chars: std::collections::HashSet<&char> = freq1.keys().chain(freq2.keys()).collect();
    
    if all_chars.is_empty() {
        return 1.0;
    }
    
    let mut total_diff = 0.0;
    for &ch in &all_chars {
        let f1 = freq1.get(ch).unwrap_or(&0.0);
        let f2 = freq2.get(ch).unwrap_or(&0.0);
        total_diff += (f1 - f2).abs();
    }
    
    1.0 - (total_diff / all_chars.len() as f64).min(1.0)
}

fn calculate_confidence(scores: &[f64]) -> f64 {
    if scores.is_empty() {
        return 0.0;
    }
    
    let mean = scores.iter().sum::<f64>() / scores.len() as f64;
    let variance = scores.iter()
        .map(|&score| (score - mean).powi(2))
        .sum::<f64>() / scores.len() as f64;
    
    // Higher variance = lower confidence
    1.0 - variance.sqrt().min(1.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_style_analysis() {
        let text = "Hello world. This is a test. How are you?";
        let profile = analyze_writing_style(text);
        
        assert!(profile.avg_sentence_length > 0.0);
        assert!(profile.vocabulary_richness > 0.0);
        assert!(profile.function_word_ratio > 0.0);
    }
    
    #[test]
    fn test_style_comparison() {
        let text1 = "Short sentences. Very simple. Easy to read.";
        let text2 = "This is a much longer sentence with more complex vocabulary and structure.";
        
        let profile1 = analyze_writing_style(text1);
        let profile2 = analyze_writing_style(text2);
        let comparison = compare_styles(&profile1, &profile2);
        
        assert!(comparison.similarity_score >= 0.0);
        assert!(comparison.similarity_score <= 1.0);
        assert!(comparison.confidence >= 0.0);
        assert!(comparison.confidence <= 1.0);
    }
}