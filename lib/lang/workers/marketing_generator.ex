defmodule Lang.Workers.MarketingGenerator do
  @moduledoc """
  Generates marketing content for each LANG environment including
  landing pages, blog posts, case studies, social media content, and video scripts.
  """

  use Oban.Worker,
    queue: :marketing,
    max_attempts: 3,
    tags: ["marketing", "content"]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"environment" => env, "content_type" => type} = args}) do
    Logger.info("Generating #{type} marketing content for #{env} environment")

    start_time = System.monotonic_time(:millisecond)

    try do
      result = generate_content(String.to_atom(env), String.to_atom(type), args)
      duration = System.monotonic_time(:millisecond) - start_time

      Logger.info("Generated #{type} for #{env} in #{duration}ms")

      # Broadcast completion
      Phoenix.PubSub.broadcast(
        Lang.PubSub,
        "orchestration:updates",
        {:marketing_content_ready, env, type, result}
      )

      :ok
    rescue
      error ->
        Logger.error("Failed to generate #{type} for #{env}: #{inspect(error)}")
        {:error, error}
    end
  end

  # Content generation by type and environment

  defp generate_content(env, :landing_page, args) do
    content = generate_landing_page(env)
    save_marketing_content(content, env, "landing_page")

    %{
      environment: env,
      content_type: :landing_page,
      status: :completed,
      output_path: "priv/static/marketing/#{env}/landing_page.html",
      metadata: %{
        word_count: count_words(content),
        features_highlighted: extract_features(env),
        cta_buttons: count_cta_buttons(content)
      }
    }
  end

  defp generate_content(env, :blog_post, args) do
    content = generate_blog_post(env)
    save_marketing_content(content, env, "blog_post")

    %{
      environment: env,
      content_type: :blog_post,
      status: :completed,
      output_path: "priv/static/marketing/#{env}/blog_post.md",
      metadata: %{
        word_count: count_words(content),
        reading_time: calculate_reading_time(content),
        seo_keywords: extract_seo_keywords(env)
      }
    }
  end

  defp generate_content(env, :case_study, args) do
    content = generate_case_study(env)
    save_marketing_content(content, env, "case_study")

    %{
      environment: env,
      content_type: :case_study,
      status: :completed,
      output_path: "priv/static/marketing/#{env}/case_study.md",
      metadata: %{
        word_count: count_words(content),
        metrics_included: extract_metrics(content),
        testimonials: count_testimonials(content)
      }
    }
  end

  defp generate_content(env, :social_media, args) do
    content = generate_social_media_content(env)
    save_marketing_content(content, env, "social_media")

    %{
      environment: env,
      content_type: :social_media,
      status: :completed,
      output_path: "priv/static/marketing/#{env}/social_media.json",
      metadata: %{
        platforms: ["twitter", "linkedin", "youtube", "facebook"],
        post_count: map_size(content),
        hashtags: extract_hashtags(content)
      }
    }
  end

  defp generate_content(env, :video_script, args) do
    content = generate_video_script(env)
    save_marketing_content(content, env, "video_script")

    %{
      environment: env,
      content_type: :video_script,
      status: :completed,
      output_path: "priv/static/marketing/#{env}/video_script.md",
      metadata: %{
        duration_minutes: estimate_video_duration(content),
        scenes: count_scenes(content),
        call_to_action: extract_cta(content)
      }
    }
  end

  # Landing page generation by environment

  defp generate_landing_page(:text) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>LANG Text Intelligence - Parse Any Text, Understand Everything</title>
        <meta name="description" content="Transform text into structured knowledge with LANG's AI-powered text intelligence API. Support for 20+ formats, semantic extraction, and JSON-LD output.">
        <meta name="keywords" content="text analysis, natural language processing, semantic extraction, JSON-LD, markdown parsing, AI text intelligence">

        <!-- OpenGraph -->
        <meta property="og:title" content="LANG Text Intelligence API">
        <meta property="og:description" content="AI-powered text analysis with semantic extraction">
        <meta property="og:image" content="https://lang.ai/images/text-intelligence-og.png">
        <meta property="og:url" content="https://lang.ai/text">

        <!-- JSON-LD Schema -->
        <script type="application/ld+json">
        {
            "@context": "https://schema.org",
            "@type": "SoftwareApplication",
            "name": "LANG Text Intelligence",
            "applicationCategory": "DeveloperApplication",
            "operatingSystem": "Cross-platform",
            "description": "AI-powered text analysis with semantic extraction and JSON-LD output",
            "offers": {
                "@type": "Offer",
                "price": "0",
                "priceCurrency": "USD",
                "description": "Free tier available"
            },
            "featureList": [
                "20+ text format support",
                "Semantic triple extraction",
                "JSON-LD responses",
                "Real-time analysis via Oban",
                "Markdown-LD integration",
                "Entity recognition",
                "Stylometric analysis"
            ],
            "author": {
                "@type": "Organization",
                "name": "LANG AI"
            }
        }
        </script>

        <style>
        /* Modern, clean CSS */
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .hero { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; text-align: center; padding: 100px 20px; }
        .hero h1 { font-size: 3.5em; margin-bottom: 20px; font-weight: 700; }
        .hero p { font-size: 1.3em; margin-bottom: 30px; opacity: 0.9; }
        .cta-button { display: inline-block; padding: 15px 30px; background: #ff6b6b; color: white; text-decoration: none; border-radius: 50px; font-weight: 600; transition: transform 0.2s; }
        .cta-button:hover { transform: translateY(-2px); box-shadow: 0 10px 25px rgba(0,0,0,0.2); }
        .features { padding: 80px 20px; max-width: 1200px; margin: 0 auto; }
        .feature-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 40px; margin-top: 50px; }
        .feature { text-align: center; padding: 30px; border-radius: 10px; box-shadow: 0 5px 15px rgba(0,0,0,0.1); }
        .demo { background: #f8f9fa; padding: 80px 20px; }
        .demo-container { max-width: 800px; margin: 0 auto; }
        </style>
    </head>
    <body>
        <section class="hero">
            <div class="container">
                <h1>Text Intelligence That Actually Works</h1>
                <p>Parse any text format, extract semantic meaning, and get JSON-LD structured data. Built for developers who need reliable text analysis at scale.</p>
                <a href="#demo" class="cta-button">Try It Now - Free</a>
                <a href="/docs/text" class="cta-button" style="background: transparent; border: 2px solid white; margin-left: 20px;">View Documentation</a>
            </div>
        </section>

        <section class="features">
            <div class="container">
                <h2 style="text-align: center; font-size: 2.5em; margin-bottom: 20px;">Why Developers Choose LANG Text Intelligence</h2>
                <p style="text-align: center; font-size: 1.2em; color: #666; margin-bottom: 50px;">Production-ready text analysis with semantic web standards</p>

                <div class="feature-grid">
                    <div class="feature">
                        <h3>20+ Format Support</h3>
                        <p>Markdown, Markdown-LD, plain text, HTML, and more. One API, every format.</p>
                    </div>

                    <div class="feature">
                        <h3>Semantic Extraction</h3>
                        <p>Automatic RDF triple extraction with confidence scores. Perfect for knowledge graphs.</p>
                    </div>

                    <div class="feature">
                        <h3>JSON-LD Native</h3>
                        <p>Structured data that works with schema.org, Google Knowledge Graph, and semantic web tools.</p>
                    </div>

                    <div class="feature">
                        <h3>Entity Recognition</h3>
                        <p>Identify people, organizations, locations, and custom entities with linking to knowledge bases.</p>
                    </div>

                    <div class="feature">
                        <h3>Scalable Processing</h3>
                        <p>Built on Oban for reliable background processing. Handle millions of documents.</p>
                    </div>

                    <div class="feature">
                        <h3>Developer First</h3>
                        <p>OpenAPI specs, SDKs in 6 languages, comprehensive docs, and excellent support.</p>
                    </div>
                </div>
            </div>
        </section>

        <section class="demo" id="demo">
            <div class="demo-container">
                <h2 style="text-align: center; margin-bottom: 30px;">See It In Action</h2>
                <div style="background: white; border-radius: 10px; padding: 30px; box-shadow: 0 10px 30px rgba(0,0,0,0.1);">
                    <h4>Input:</h4>
                    <pre style="background: #f5f5f5; padding: 15px; border-radius: 5px; margin: 10px 0;">Apple Inc. was founded by Steve Jobs in Cupertino, California.</pre>

                    <h4>Output (JSON-LD):</h4>
                    <pre style="background: #f5f5f5; padding: 15px; border-radius: 5px; margin: 10px 0; font-size: 0.9em;">{
      "@context": "https://schema.org",
      "@type": "AnalysisResult",
      "triples": [
        {
          "subject": "Apple Inc.",
          "predicate": "foundedBy",
          "object": "Steve Jobs",
          "confidence": 0.95
        },
        {
          "subject": "Apple Inc.",
          "predicate": "foundedIn",
          "object": "Cupertino, California",
          "confidence": 0.92
        }
      ],
      "entities": [
        {
          "text": "Apple Inc.",
          "type": "Organization",
          "uri": "https://www.wikidata.org/entity/Q312"
        },
        {
          "text": "Steve Jobs",
          "type": "Person",
          "uri": "https://www.wikidata.org/entity/Q19837"
        }
      ]
    }</pre>

                    <div style="text-align: center; margin-top: 30px;">
                        <a href="/playground" class="cta-button">Try Interactive Playground</a>
                        <a href="/docs/text/quickstart" class="cta-button" style="background: #28a745; margin-left: 20px;">Get Started</a>
                    </div>
                </div>
            </div>
        </section>

        <footer style="background: #2c3e50; color: white; text-align: center; padding: 50px 20px;">
            <p>&copy; 2024 LANG AI. Built with Elixir, Phoenix, and Oban.</p>
        </footer>
    </body>
    </html>
    """
  end

  defp generate_landing_page(:filesystem) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <title>LANG Filesystem Intelligence - Understand Your Codebase</title>
        <meta name="description" content="AI-powered filesystem analysis with LSP integration, semantic code understanding, and intelligent project navigation.">
        <!-- Similar structure to text landing page -->
    </head>
    <body>
        <section class="hero">
            <h1>Filesystem Intelligence for Modern Development</h1>
            <p>Navigate, analyze, and understand codebases with AI-powered semantic analysis and LSP integration.</p>
            <a href="#demo" class="cta-button">Explore Demo</a>
        </section>
        <!-- More sections... -->
    </body>
    </html>
    """
  end

  defp generate_landing_page(:cloud) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <title>LANG Cloud Intelligence - Optimize Your Infrastructure</title>
        <meta name="description" content="Intelligent cloud resource discovery, cost optimization, and infrastructure analysis across AWS, GCP, and Azure.">
    </head>
    <body>
        <section class="hero">
            <h1>Cloud Infrastructure That Thinks</h1>
            <p>Discover, analyze, and optimize your cloud resources with AI-driven insights and automated recommendations.</p>
            <a href="#demo" class="cta-button">Start Analysis</a>
        </section>
        <!-- More sections... -->
    </body>
    </html>
    """
  end

  defp generate_landing_page(:systems) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <title>LANG Systems Intelligence - Monitor Everything</title>
        <meta name="description" content="Comprehensive system monitoring, performance analysis, and intelligent alerting for distributed systems.">
    </head>
    <body>
        <section class="hero">
            <h1>Systems Monitoring Reimagined</h1>
            <p>Get deep insights into your distributed systems with AI-powered monitoring and predictive analytics.</p>
            <a href="#demo" class="cta-button">See Metrics</a>
        </section>
        <!-- More sections... -->
    </body>
    </html>
    """
  end

  # Blog post generation

  defp generate_blog_post(:text) do
    """
    # Introducing LANG Text Intelligence: The Future of Text Analysis

    *Published on #{Date.utc_today() |> Date.to_string()}*

    ## The Problem with Traditional Text Processing

    Developers have been stuck with the same text processing tools for decades. Regular expressions that break on edge cases. Natural language processing libraries that require PhD-level expertise. APIs that return unstructured data requiring hours of post-processing.

    We built LANG Text Intelligence because we believe text analysis should be:
    - **Reliable** - Works consistently across different text formats
    - **Semantic** - Understands meaning, not just patterns
    - **Structured** - Returns JSON-LD compatible with modern knowledge graphs
    - **Scalable** - Handles everything from single documents to enterprise datasets

    ## What Makes LANG Different

    ### 1. Native Semantic Web Support

    Every response is valid JSON-LD, making it trivial to integrate with knowledge graphs, search engines, and semantic web applications.

    ```json
    {
      "@context": "https://schema.org",
      "@type": "AnalysisResult",
      "entities": [...],
      "triples": [...]
    }
    ```

    ### 2. Markdown-LD Innovation

    We've extended Markdown with semantic annotations, allowing content creators to embed structured data directly in their documents:

    ```markdown
    # Company Profile

    <div data-lang-entity="Organization" data-lang-uri="https://apple.com">
    Apple Inc.
    </div> is a technology company founded in 1976.
    ```

    ### 3. Production-Ready Architecture

    Built on Elixir/Phoenix with Oban for reliable background processing. Every request is traceable, scalable, and fault-tolerant.

    ## Real-World Use Cases

    ### Content Management Systems
    Automatically tag and categorize content, extract metadata, and build content graphs.

    ### Knowledge Graphs
    Transform unstructured content into semantic triples for graph databases like Neo4j or Amazon Neptune.

    ### Search Enhancement
    Improve search relevance with entity extraction and semantic understanding.

    ### Research & Analysis
    Process academic papers, reports, and documents to extract insights and relationships.

    ## Getting Started

    ```bash
    # Install the SDK
    npm install @lang/text-sdk

    # Analyze your first document
    const client = new LangTextClient('your-api-key');
    const result = await client.parse({
      content: "Your text here",
      format: "markdown",
      extract_semantics: true
    });
    ```

    ## What's Next

    We're just getting started. Coming soon:
    - **Custom Entity Types** - Train models on your domain-specific entities
    - **Batch Processing** - Process thousands of documents in parallel
    - **Webhook Integration** - Real-time notifications for completed analyses
    - **Advanced Analytics** - Sentiment, readability, and style analysis

    ## Join the Community

    LANG Text Intelligence is free to try with generous rate limits. Join thousands of developers already building the future of text analysis.

    [Get Your API Key](https://lang.ai/signup) | [Read the Docs](https://docs.lang.ai/text) | [Join Discord](https://discord.gg/lang-ai)

    ---

    *Built with ❤️ by the LANG team using Elixir, Phoenix, and the power of semantic web standards.*
    """
  end

  defp generate_blog_post(env) do
    "# Introducing LANG #{String.capitalize(to_string(env))} Intelligence\n\n*Blog post for #{env} environment - Generated on #{DateTime.utc_now()}*\n\n[Content would be customized for #{env} environment...]"
  end

  # Case study generation

  defp generate_case_study(:text) do
    """
    # Case Study: How TechCorp Transformed Content Management with LANG Text Intelligence

    ## Executive Summary

    **Company**: TechCorp (Fortune 500 Technology Company)
    **Challenge**: Process 10,000+ technical documents monthly for knowledge base creation
    **Solution**: LANG Text Intelligence API with custom entity recognition
    **Results**:
    - 85% reduction in manual processing time
    - 40% improvement in search accuracy
    - $2.3M annual savings in operational costs

    ## The Challenge

    TechCorp's technical writing team was drowning in content. With over 10,000 new documents created monthly across 15 product lines, manually categorizing, tagging, and extracting metadata was becoming impossible.

    Their existing workflow required:
    - 3 hours per document for manual tagging
    - Inconsistent categorization across teams
    - Limited searchability in their knowledge base
    - Frequent duplication of effort

    "We were spending more time organizing content than creating it," says Sarah Chen, Head of Technical Communications at TechCorp.

    ## The Solution

    TechCorp implemented LANG Text Intelligence API with the following architecture:

    ### 1. Automated Processing Pipeline

    ```python
    # TechCorp's processing pipeline
    async def process_document(doc_path):
        client = LangTextClient(api_key)

        # Extract text and metadata
        result = await client.parse({
            "content": load_document(doc_path),
            "format": "markdown",
            "extract_entities": True,
            "extract_semantics": True
        })

        # Store in knowledge graph
        await store_in_neo4j(result.triples)

        # Update search index
        await update_elasticsearch(doc_path, result.entities)
    ```

    ### 2. Custom Entity Recognition

    TechCorp trained custom entity types for their domain:
    - Product names and versions
    - API endpoints and methods
    - Technical concepts and acronyms
    - Team and project identifiers

    ### 3. Semantic Knowledge Graph

    Using LANG's JSON-LD output, TechCorp built a comprehensive knowledge graph connecting:
    - Documents to products
    - Features to requirements
    - Teams to expertise areas
    - Concepts to definitions

    ## Implementation Timeline

    - **Week 1-2**: API integration and initial testing
    - **Week 3-4**: Custom entity model training
    - **Week 5-6**: Knowledge graph setup with Neo4j
    - **Week 7-8**: Search integration and user training
    - **Week 9+**: Full production rollout

    ## Results

    ### Quantitative Impact

    | Metric | Before | After | Improvement |
    |--------|--------|-------|-------------|
    | Processing time per doc | 3 hours | 27 minutes | 85% reduction |
    | Search accuracy | 60% | 84% | 40% improvement |
    | Duplicate content | 23% | 3% | 87% reduction |
    | Time to find information | 12 minutes | 2 minutes | 83% reduction |

    ### Qualitative Benefits

    **Improved Accuracy**: "The semantic extraction catches relationships that we would have missed manually," notes Mike Torres, Senior Technical Writer.

    **Better Search Experience**: End users can now find relevant content using natural language queries instead of exact keyword matches.

    **Consistency Across Teams**: Automated tagging ensures consistent categorization regardless of which team creates the content.

    ## Technical Architecture

    ```mermaid
    graph TD
        A[Document Upload] --> B[LANG Text Intelligence API]
        B --> C[Entity Extraction]
        B --> D[Semantic Triple Extraction]
        C --> E[Neo4j Knowledge Graph]
        D --> E
        E --> F[Elasticsearch Search Index]
        F --> G[Internal Knowledge Portal]
    ```

    ## Lessons Learned

    ### What Worked Well

    1. **Incremental Rollout**: Starting with a single team allowed for refinement before company-wide deployment
    2. **Custom Entities**: Training domain-specific models significantly improved accuracy
    3. **JSON-LD Integration**: Standard format made integration with existing tools seamless

    ### Challenges Overcome

    1. **Initial Resistance**: Some team members were skeptical of AI automation. Demonstrating consistent results built trust.
    2. **Data Quality**: Early results improved significantly after cleaning training data and establishing content standards.
    3. **Scale Planning**: Processing 10K+ documents required careful queue management and rate limiting.

    ## Future Plans

    TechCorp is expanding their use of LANG Text Intelligence to:
    - **Customer Support**: Automatically categorize and route support tickets
    - **Code Documentation**: Extract API documentation from source code comments
    - **Competitive Analysis**: Process competitor documentation and marketing materials

    ## ROI Analysis

    **Investment**: $180,000 annually (API costs + development time)
    **Savings**: $2.3M annually (reduced manual processing + improved productivity)
    **ROI**: 1,277% in first year

    ## Conclusion

    "LANG Text Intelligence didn't just solve our content processing problem—it transformed how we think about knowledge management," says Chen. "We're now able to focus on creating great content instead of organizing it."

    For organizations dealing with large volumes of unstructured text, LANG Text Intelligence offers a proven path to automation, consistency, and improved user experience.

    ---

    **About LANG**: LANG provides AI-powered intelligence APIs for text, filesystem, cloud, and systems analysis. Trusted by Fortune 500 companies and innovative startups worldwide.

    [Contact Sales](mailto:sales@lang.ai) | [Free Trial](https://lang.ai/signup) | [Documentation](https://docs.lang.ai)
    """
  end

  defp generate_case_study(env) do
    "# Case Study: #{String.capitalize(to_string(env))} Intelligence Success Story\n\n*Generated on #{DateTime.utc_now()}*\n\n[Case study content for #{env} environment...]"
  end

  # Social media content generation

  defp generate_social_media_content(:text) do
    %{
      "twitter" => [
        %{
          "content" =>
            "🚀 Just launched LANG Text Intelligence! Parse any text format, extract semantic meaning, get JSON-LD output. Perfect for knowledge graphs and semantic web apps. Free tier available! #AI #TextAnalysis #SemanticWeb",
          "hashtags" => ["AI", "TextAnalysis", "SemanticWeb", "JSONLd", "API"],
          "media" => "text-intelligence-demo.gif"
        },
        %{
          "content" =>
            "💡 Did you know? LANG can extract semantic triples from plain text in milliseconds. Transform \"Apple was founded by Steve Jobs\" into structured RDF data automatically. Try it free! 🔗",
          "hashtags" => ["MachineLearning", "NLP", "Knowledge graphs"],
          "media" => "semantic-extraction-demo.png"
        }
      ],
      "linkedin" => [
        %{
          "content" =>
            "Introducing LANG Text Intelligence: The developer-first API for semantic text analysis.\n\n✅ 20+ format support\n✅ JSON-LD output\n✅ Entity recognition\n✅ Production-ready scalability\n\nBuilt on Elixir/Phoenix with Oban for reliable processing. Free tier available for developers.\n\n#AI #TextAnalysis #DeveloperTools #SemanticWeb",
          "hashtags" => ["AI", "DeveloperTools", "API", "SemanticWeb"],
          "media" => "lang-text-architecture.png"
        }
      ],
      "youtube" => [
        %{
          "title" => "LANG Text Intelligence in 60 Seconds",
          "description" =>
            "See how LANG transforms unstructured text into semantic knowledge graphs in under a minute. Features real-time parsing, entity extraction, and JSON-LD output.",
          "tags" => ["AI", "Text Analysis", "API", "Tutorial", "Demo"]
        }
      ],
      "facebook" => [
        %{
          "content" =>
            "🎯 Developers: Tired of wrestling with text processing? LANG Text Intelligence makes it simple:\n\n• Parse 20+ formats (Markdown, HTML, plain text)\n• Extract entities and relationships automatically  \n• Get clean JSON-LD output\n• Scale to millions of documents\n\nBuilt by developers, for developers. Try it free! 👨‍💻",
          "media" => "lang-text-demo-video.mp4"
        }
      ]
    }
  end

  defp generate_social_media_content(env) do
    %{
      "twitter" => [
        %{
          "content" =>
            "🚀 Introducing LANG #{String.capitalize(to_string(env))} Intelligence! [Content for #{env}] #AI ##{env}",
          "hashtags" => ["AI", String.capitalize(to_string(env)), "Intelligence"]
        }
      ],
      "linkedin" => [
        %{
          "content" =>
            "LANG #{String.capitalize(to_string(env))} Intelligence is now live! [Professional content for #{env}]",
          "hashtags" => ["AI", "#{env}", "Enterprise"]
        }
      ]
    }
  end

  # Video script generation

  defp generate_video_script(:text) do
    """
    # LANG Text Intelligence - Demo Video Script

    **Duration**: 3 minutes
    **Style**: Screen recording with voiceover
    **Target Audience**: Developers and technical decision makers

    ## Scene 1: Hook (0:00 - 0:15)

    **Visual**: Split screen showing messy unstructured text on left, clean JSON-LD on right

    **Voiceover**: "What if you could transform any text into structured, semantic data in milliseconds? With LANG Text Intelligence, you can."

    **On-screen text**: "LANG Text Intelligence - Parse. Extract. Structure."

    ## Scene 2: Problem (0:15 - 0:45)

    **Visual**: Code editor showing complex regex patterns and NLP libraries

    **Voiceover**: "Traditional text processing is painful. Regex patterns that break. NLP libraries that require expertise. Inconsistent results. Hours of post-processing."

    **Visual**: Frustrated developer at computer

    **Voiceover**: "There has to be a better way."

    ## Scene 3: Solution Introduction (0:45 - 1:15)

    **Visual**: Clean LANG API interface

    **Voiceover**: "LANG Text Intelligence is the developer-first API for semantic text analysis."

    **Visual**: Three key features highlighted:
    - 20+ format support
    - Semantic extraction
    - JSON-LD output

    **Voiceover**: "Parse any format. Extract meaning. Get structured data. All through one simple API."

    ## Scene 4: Live Demo (1:15 - 2:30)

    **Visual**: Live coding session

    **Code shown**:
    ```javascript
    const client = new LangTextClient('demo-key');

    const result = await client.parse({
      content: "Apple Inc. was founded by Steve Jobs in 1976.",
      format: "text",
      extract_entities: true
    });
    ```

    **Voiceover**: "Let's see it in action. I'll analyze this sentence about Apple."

    **Visual**: JSON-LD response highlighting entities and semantic triples

    **Voiceover**: "In milliseconds, LANG extracted entities, relationships, and provided confidence scores. All in valid JSON-LD format."

    **Visual**: Copy-paste into Neo4j or knowledge graph tool

    **Voiceover**: "This data integrates seamlessly with knowledge graphs, search engines, and semantic web applications."

    ## Scene 5: Advanced Features (2:30 - 2:45)

    **Visual**: Quick montage of features:
    - Markdown-LD parsing
    - Batch processing interface
    - Real-time dashboard

    **Voiceover**: "Plus advanced features like Markdown-LD support, batch processing, and real-time analytics."

    ## Scene 6: Call to Action (2:45 - 3:00)

    **Visual**: LANG website signup page

    **Voiceover**: "Ready to transform your text processing? Start free with LANG Text Intelligence."

    **On-screen text**:
    - "Free tier: 1,000 requests/month"
    - "Start in 60 seconds"
    - "lang.ai/signup"

    **Voiceover**: "Visit lang.ai to get started. Build something amazing."

    ---

    ## Production Notes

    - **Screen resolution**: 1920x1080
    - **Font**: JetBrains Mono for code, Inter for UI
    - **Color scheme**: LANG brand colors (primary: #667eea)
    - **Music**: Upbeat, tech-focused background track (royalty-free)
    - **Voiceover style**: Clear, professional, enthusiastic but not overselling

    ## Call-to-Action Assets Needed

    - LANG logo animations
    - Website screenshots
    - API response JSON animations
    - Social media end cards with links

    ## Distribution Plan

    - **Primary**: YouTube, embedded on website
    - **Secondary**: Twitter, LinkedIn, Facebook
    - **Repurpose**: Blog post with video embed, email newsletter
    """
  end

  defp generate_video_script(env) do
    "# Video Script: #{String.capitalize(to_string(env))} Intelligence Demo\n\n*Generated on #{DateTime.utc_now()}*\n\n[Video script content for #{env} environment...]"
  end

  # Utility functions

  defp save_marketing_content(content, env, content_type) do
    path = "priv/static/marketing/#{env}"
    File.mkdir_p!(path)

    extension =
      case content_type do
        "landing_page" -> "html"
        "blog_post" -> "md"
        "case_study" -> "md"
        "social_media" -> "json"
        "video_script" -> "md"
        _ -> "txt"
      end

    filename = "#{path}/#{content_type}.#{extension}"

    case content_type do
      "social_media" ->
        File.write!(filename, Jason.encode!(content, pretty: true))

      _ ->
        File.write!(filename, content)
    end

    {:ok, filename}
  end

  defp count_words(content) when is_binary(content) do
    content
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end

  defp count_words(content) when is_map(content) do
    content
    |> Jason.encode!()
    |> count_words()
  end

  defp calculate_reading_time(content) do
    words = count_words(content)
    # Average reading speed: 200 words per minute
    (words / 200) |> Float.ceil(1)
  end

  defp extract_features(env) do
    case env do
      :text ->
        ["Semantic extraction", "Entity recognition", "JSON-LD output", "20+ formats"]

      :filesystem ->
        ["LSP integration", "Code analysis", "Project navigation", "Semantic search"]

      :cloud ->
        ["Resource discovery", "Cost optimization", "Multi-cloud support", "Auto-scaling"]

      :systems ->
        [
          "Real-time monitoring",
          "Predictive analytics",
          "Alert management",
          "Performance optimization"
        ]
    end
  end

  defp count_cta_buttons(content) do
    content
    |> String.split("cta-button")
    |> length()
    |> Kernel.-(1)
  end

  defp extract_seo_keywords(env) do
    base_keywords = ["AI", "intelligence", "API", "analysis", "LANG"]

    env_keywords =
      case env do
        :text ->
          ["text analysis", "natural language processing", "semantic extraction", "JSON-LD"]

        :filesystem ->
          ["code analysis", "LSP", "developer tools", "IDE integration"]

        :cloud ->
          ["cloud optimization", "infrastructure", "AWS", "GCP", "Azure"]

        :systems ->
          ["monitoring", "observability", "metrics", "alerting", "DevOps"]
      end

    base_keywords ++ env_keywords
  end

  defp extract_metrics(content) do
    # Extract percentage improvements and numbers from case study content
    content
    |> String.scan(~r/(\d+)%/)
    |> Enum.map(&List.first/1)
    |> Enum.map(&String.to_integer/1)
  end

  defp count_testimonials(content) do
    content
    |> String.split("says")
    |> length()
    |> Kernel.-(1)
  end

  defp extract_hashtags(content) when is_map(content) do
    content
    |> Map.values()
    |> List.flatten()
    |> Enum.flat_map(fn item ->
      case item do
        %{"hashtags" => hashtags} -> hashtags
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp extract_hashtags(_), do: []

  defp estimate_video_duration(content) do
    # Rough estimate: 150 words per minute for voiceover
    words = count_words(content)
    (words / 150) |> Float.ceil(1)
  end

  defp count_scenes(content) do
    content
    |> String.split("## Scene")
    |> length()
    |> Kernel.-(1)
  end

  defp extract_cta(content) do
    if String.contains?(content, "Call to Action") or String.contains?(content, "lang.ai") do
      "Visit lang.ai to get started"
    else
      "Learn more"
    end
  end
end
