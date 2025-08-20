# Stylometric Analysis & Writing Fingerprinting

Advanced writing style analysis for authorship attribution, style consistency, and privacy protection.

## Overview

LANG's stylometric analysis engine provides:

- **Writing Fingerprinting**: Unique style identification across linguistic dimensions
- **Authorship Attribution**: Compare samples to determine likely authorship
- **Style Obfuscation**: Modify writing patterns while preserving meaning
- **Privacy Protection**: Anonymize writing style for sensitive communications

## Core Capabilities

### Writing Style Analysis

Comprehensive analysis across multiple linguistic dimensions:

```elixir
{:ok, analysis} = Lang.Stylometrics.AnalysisEngine.analyze_writing_style("""
  Artificial intelligence represents a paradigm shift in computational capabilities. 
  The implications extend far beyond mere algorithmic efficiency, encompassing 
  fundamental changes in how we approach problem-solving processes.
""")
```

Returns detailed fingerprint including:
- **Linguistic Features**: Sentence length, word complexity, vocabulary richness
- **Syntactic Features**: Sentence structure patterns, voice usage
- **Lexical Features**: Word choice patterns, technical terminology usage
- **Stylistic Features**: Formality level, emotional intensity, subjectivity

### Authorship Attribution

Compare writing samples for authorship determination:

```bash
curl -X POST http://localhost:4000/api/v1/stylometrics/compare \
  -H "Content-Type: application/json" \
  -d '{
    "sample1": "First writing sample with distinctive patterns...",
    "sample2": "Second sample to compare for authorship...",
    "options": {
      "detailed_comparison": true,
      "confidence_threshold": 0.7
    }
  }'
```

Response includes:
- Similarity score (0.0 to 1.0)
- Likely same author determination
- Confidence level assessment
- Feature-by-feature comparison
- Distinctive differences identified

## Use Cases

### Content Authentication

Verify document authorship and detect ghostwriting:

```elixir
# Verify blog post consistency
{:ok, comparison} = Lang.Stylometrics.AnalysisEngine.compare_writing_styles(
  previous_blog_posts,
  new_submission
)

if comparison.likely_same_author and comparison.confidence_level == :high do
  IO.puts("Authorship verified")
else
  IO.puts("Potential ghostwriter detected")
end
```

### Privacy Protection

Anonymize writing style for sensitive communications:

```elixir
# Generate obfuscation suggestions
{:ok, suggestions} = Lang.Stylometrics.AnalysisEngine.generate_obfuscation_suggestions(
  sensitive_document,
  :academic  # Target style
)

# Apply transformations
{:ok, result} = Lang.Stylometrics.AnalysisEngine.apply_obfuscation(
  sensitive_document,
  suggestions.obfuscation_suggestions,
  %{intensity: 0.7, preserve_meaning: true}
)

IO.puts("Original fingerprint: #{result.original_content |> get_fingerprint()}")
IO.puts("Obfuscated fingerprint: #{result.transformed_content |> get_fingerprint()}")
```

### Brand Voice Consistency

Ensure consistent brand voice across content:

```elixir
# Analyze brand voice consistency
brand_samples = [
  load_content("marketing/email1.txt"),
  load_content("marketing/email2.txt"),
  load_content("marketing/blog_post.txt")
]

consistency_scores = for {sample1, sample2} <- combinations(brand_samples) do
  {:ok, comparison} = Lang.Stylometrics.AnalysisEngine.compare_writing_styles(sample1, sample2)
  comparison.similarity_score
end

avg_consistency = Enum.sum(consistency_scores) / length(consistency_scores)
IO.puts("Brand voice consistency: #{avg_consistency * 100}%")
```

## API Reference

### Analyze Writing Style

```http
POST /api/v1/stylometrics/analyze
Content-Type: application/json

{
  "content": "Your writing sample here...",
  "options": {
    "detailed_features": true,
    "confidence_threshold": 0.7,
    "include_fingerprint": true
  }
}
```

### Compare Samples

```http
POST /api/v1/stylometrics/compare
Content-Type: application/json

{
  "sample1": "First writing sample...",
  "sample2": "Second writing sample...",
  "options": {
    "detailed_comparison": true,
    "feature_breakdown": true
  }
}
```

### Generate Obfuscation

```http
POST /api/v1/stylometrics/obfuscate
Content-Type: application/json

{
  "content": "Text to obfuscate...",
  "target_style": "academic",
  "options": {
    "intensity": 0.7,
    "preserve_meaning": true,
    "transformation_types": ["lexical", "syntactic", "stylistic"]
  }
}
```

## Advanced Features

### Custom Style Profiles

Create and match against custom style profiles:

```elixir
# Build executive communication profile
executive_samples = load_executive_emails()
{:ok, executive_profile} = build_style_profile(executive_samples)

# Test new content against profile
{:ok, analysis} = analyze_writing_style(new_email)
match_score = calculate_profile_match(analysis, executive_profile)

if match_score > 0.8 do
  IO.puts("Matches executive communication style")
end
```

### Temporal Style Analysis

Track writing style changes over time:

```elixir
# Analyze author style evolution
documents = load_chronological_documents(author_id)

style_timeline = documents
|> Enum.map(fn doc ->
  {:ok, analysis} = analyze_writing_style(doc.content)
  {doc.date, analysis.fingerprint}
end)
|> detect_style_shifts()

IO.puts("Major style shifts detected at: #{Enum.join(style_timeline.shift_points, ", ")}")
```

### Multi-language Support

Analyze style across different languages:

```elixir
# Cross-language style comparison
{:ok, english_analysis} = analyze_writing_style(english_text, %{language: "en"})
{:ok, spanish_analysis} = analyze_writing_style(spanish_text, %{language: "es"})

cross_language_similarity = compare_cross_language_styles(
  english_analysis,
  spanish_analysis
)
```

## Configuration

### Analysis Sensitivity

```elixir
# config/config.exs
config :lang, :stylometrics,
  # Minimum text length for reliable analysis
  min_sample_length: 100,
  
  # Confidence thresholds
  confidence_thresholds: %{
    low: 0.3,
    medium: 0.6,
    high: 0.8,
    very_high: 0.9
  },
  
  # Feature weights for fingerprinting
  feature_weights: %{
    linguistic: 0.35,
    syntactic: 0.25,
    lexical: 0.20,
    stylistic: 0.20
  },
  
  # Obfuscation settings
  obfuscation: %{
    max_intensity: 0.9,
    preserve_meaning_threshold: 0.85,
    available_transformations: [:lexical, :syntactic, :stylistic]
  }
```

### Performance Optimization

```elixir
# Background processing for large-scale analysis
config :lang, Oban,
  queues: [
    stylometrics_analysis: 10,
    batch_comparison: 5,
    obfuscation: 3
  ]

# Cache frequently accessed profiles
config :lang, :stylometrics_cache,
  ttl: 3600, # 1 hour
  max_profiles: 1000
```

## Best Practices

### Sample Size Guidelines

| Text Length | Analysis Reliability | Recommended Use |
|-------------|---------------------|-----------------|
| < 100 words | Low | Not recommended |
| 100-500 words | Medium | Basic comparison |
| 500-2000 words | High | Authorship attribution |
| > 2000 words | Very High | Detailed profiling |

### Accuracy Considerations

1. **Domain Consistency**: Compare texts from similar domains for best results
2. **Time Proximity**: Recent samples provide more accurate comparisons
3. **Sample Diversity**: Multiple samples improve profile accuracy
4. **Language Consistency**: Analyze texts in the same language

### Privacy Best Practices

1. **Data Retention**: Automatically purge sensitive analyses after use
2. **Access Control**: Restrict stylometric capabilities to authorized users
3. **Audit Logging**: Log all obfuscation and comparison activities
4. **Consent Requirements**: Ensure proper consent for style analysis

## Integration Examples

### Document Review System

```elixir
defmodule DocumentReview.StyleChecker do
  def check_submission(document, expected_author) do
    with {:ok, submission_analysis} <- analyze_writing_style(document.content),
         {:ok, author_profile} <- load_author_profile(expected_author),
         similarity <- calculate_similarity(submission_analysis, author_profile) do
      
      case similarity do
        score when score > 0.8 -> {:ok, :authentic}
        score when score > 0.6 -> {:warning, :possible_collaboration}
        _ -> {:error, :likely_ghostwritten}
      end
    end
  end
end
```

### Content Moderation

```elixir
defmodule ContentModeration.StyleFilter do
  def detect_sockpuppeting(user_posts) do
    analyses = Enum.map(user_posts, &analyze_writing_style/1)
    
    # Check for multiple distinct writing styles from same user
    style_clusters = cluster_by_similarity(analyses, threshold: 0.7)
    
    if length(style_clusters) > 1 do
      {:suspicious, :multiple_writing_styles}
    else
      {:ok, :consistent_style}
    end
  end
end
```