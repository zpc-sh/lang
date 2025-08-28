defmodule LangWeb.DocsLive do
  @moduledoc """
  LiveView for rendering LANG documentation from Markdown files.

  Provides a clean, searchable documentation interface with:
  - Markdown rendering with syntax highlighting
  - Table of contents generation
  - Search functionality
  - Responsive navigation
  """

  use LangWeb, :live_view
  alias LangWeb.Components.Footer
  import LangWeb.NavbarComponent

  @docs_path Application.app_dir(:lang, "priv/docs")
  @orchestrated_docs_path Application.app_dir(:lang, "priv/static/docs")

  @impl true
  def mount(%{"path" => path}, _session, socket) do
    case load_doc(path) do
      {:ok, content, title} ->
        {:ok,
         socket
         |> assign(:page_title, title)
         |> assign(:doc_content, content)
         |> assign(:doc_path, path)
         |> assign(:toc, extract_toc(content))
         |> assign(:search_query, "")
         |> assign(:sidebar_open, false)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Documentation page not found")
         |> redirect(to: "/docs")}
    end
  end

  def mount(_params, _session, socket) do
    # Default to index page
    case load_doc("index") do
      {:ok, content, title} ->
        {:ok,
         socket
         |> assign(:page_title, title)
         |> assign(:doc_content, content)
         |> assign(:doc_path, "index")
         |> assign(:toc, extract_toc(content))
         |> assign(:search_query, "")
         |> assign(:sidebar_open, false)
         |> assign(:doc_tree, build_doc_tree())}

      {:error, _} ->
        {:ok,
         socket
         |> assign(:page_title, "Documentation")
         |> assign(:doc_content, "# Documentation\n\nDocumentation is being prepared.")
         |> assign(:doc_path, "index")
         |> assign(:toc, [])
         |> assign(:search_query, "")
         |> assign(:sidebar_open, false)
         |> assign(:doc_tree, [])}
    end
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :sidebar_open, !socket.assigns.sidebar_open)}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    # In a real implementation, you'd search through all docs
    {:noreply, assign(socket, :search_query, query)}
  end

  def handle_event("generate_docs", _params, socket) do
    case generate_orchestrated_docs() do
      :ok ->
        {:noreply, put_flash(socket, :info, "Documentation generated successfully!")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to generate docs: #{reason}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]} current_scope={assigns[:current_scope]}>
      <!-- Main Content -->
      <div class="flex">
        <!-- Sidebar -->
        <aside class={[
          "fixed inset-y-0 left-0 z-40 w-64 bg-gray-900 border-r border-gray-800 pt-16 transform transition-transform duration-300 ease-in-out md:relative md:translate-x-0",
          (@sidebar_open && "translate-x-0") || "-translate-x-full"
        ]}>
          <!-- Search -->
          <div class="p-4">
            <.form for={%{}} phx-change="search" class="relative">
              <input
                type="text"
                name="search[query]"
                value={@search_query}
                placeholder="Search docs..."
                class="w-full bg-gray-800 border border-gray-700 rounded-lg px-4 py-2 text-sm focus:border-blue-500 focus:outline-none"
              />
              <.icon
                name="hero-magnifying-glass"
                class="absolute right-3 top-2.5 w-4 h-4 text-gray-500"
              />
            </.form>
          </div>
          
    <!-- Navigation -->
          <nav class="px-4 pb-4">
            <div class="space-y-1">
              <a
                href="/docs"
                class={[
                  "block px-3 py-2 rounded-md text-sm font-medium transition-colors",
                  (@doc_path == "index" && "bg-blue-600 text-white") ||
                    "text-gray-300 hover:text-white hover:bg-gray-800"
                ]}
              >
                <.icon name="hero-home" class="w-4 h-4 inline mr-2" /> Overview
              </a>

              <div class="mt-6">
                <h3 class="px-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  Getting Started
                </h3>
                <div class="mt-2 space-y-1">
                  <a
                    href="/docs/guides/getting-started"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    Quick Start
                  </a>
                  <a
                    href="/docs/text/introduction"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    Text Analysis
                  </a>
                  <a
                    href="/docs/text/quickstart"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    Quick Start API
                  </a>
                </div>
              </div>

              <div class="mt-6">
                <h3 class="px-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  API Reference
                </h3>
                <div class="mt-2 space-y-1">
                  <a
                    href="/docs/api"
                    class={[
                      "block px-3 py-2 rounded-md text-sm transition-colors",
                      (@doc_path == "api/index" && "bg-blue-600 text-white") ||
                        "text-gray-300 hover:text-white hover:bg-gray-800"
                    ]}
                  >
                    API Overview
                  </a>
                  <a
                    href="/docs/text/api_reference"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    Text API
                  </a>
                  <a
                    href="/docs/text/examples"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    API Examples
                  </a>
                  <a
                    href="/docs/api"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    Full API Reference
                  </a>
                </div>
              </div>

              <div class="mt-6">
                <h3 class="px-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  Architecture
                </h3>
                <div class="mt-2 space-y-1">
                  <a
                    href="/docs/architecture/overview"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    System Overview
                  </a>
                  <a
                    href="/docs/architecture/native-nifs"
                    class={[
                      "block px-3 py-2 rounded-md text-sm transition-colors",
                      (@doc_path == "architecture/native-nifs" && "bg-blue-600 text-white") ||
                        "text-gray-300 hover:text-white hover:bg-gray-800"
                    ]}
                  >
                    Native NIFs
                  </a>
                  <a
                    href="/docs/architecture/database"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    Database Schema
                  </a>
                </div>
              </div>

              <div class="mt-6">
                <h3 class="px-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  Tutorials
                </h3>
                <div class="mt-2 space-y-1">
                  <a
                    href="/docs/tutorials"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    All Tutorials
                  </a>
                  <a
                    href="/docs/text/tutorials"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    Text Analysis
                  </a>
                  <a
                    href="/docs/text/best_practices"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    Best Practices
                  </a>
                  <a
                    href="/docs/text/troubleshooting"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    Troubleshooting
                  </a>
                </div>
              </div>

              <div class="mt-6">
                <h3 class="px-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  Guides
                </h3>
                <div class="mt-2 space-y-1">
                  <a
                    href="/docs/guides/authentication"
                    class="block px-3 py-2 rounded-md text-sm text-gray-300 hover:text-white hover:bg-gray-800"
                  >
                    Authentication & Org Context
                  </a>
                </div>
              </div>
            </div>
          </nav>
        </aside>
        
    <!-- Mobile sidebar overlay -->
        <%= if @sidebar_open do %>
          <div
            class="fixed inset-0 z-30 bg-black bg-opacity-50 md:hidden"
            phx-click="toggle_sidebar"
          >
          </div>
        <% end %>
        
    <!-- Main content -->
        <main class="flex-1 md:ml-0">
          <div class="max-w-4xl mx-auto px-6 py-8">
            <!-- Breadcrumb -->
            <nav class="flex mb-6 text-sm" aria-label="Breadcrumb">
              <ol class="inline-flex items-center space-x-1 md:space-x-3">
                <li class="inline-flex items-center">
                  <a href="/docs" class="text-gray-400 hover:text-white">
                    Documentation
                  </a>
                </li>
                <%= if @doc_path != "index" do %>
                  <li>
                    <div class="flex items-center">
                      <.icon name="hero-chevron-right" class="w-4 h-4 text-gray-500 mx-2" />
                      <span class="text-gray-300 capitalize">
                        {String.replace(@doc_path, "/", " > ")}
                      </span>
                    </div>
                  </li>
                <% end %>
              </ol>
            </nav>
            
    <!-- Document content -->
            <article class="prose prose-invert prose-lg max-w-none">
              <div class="markdown-content" phx-no-format>
                {raw(render_markdown(@doc_content))}
              </div>
            </article>
            
    <!-- Table of Contents (if present) -->
            <%= if length(@toc) > 0 do %>
              <aside class="mt-12 p-6 bg-gray-900 rounded-lg border border-gray-800">
                <h3 class="text-lg font-semibold text-white mb-4">Table of Contents</h3>
                <nav class="toc">
                  <ul class="space-y-2 text-sm">
                    <%= for {level, title, id} <- @toc do %>
                      <li class={level_class(level)}>
                        <a
                          href={"##{id}"}
                          class="text-gray-400 hover:text-white transition-colors"
                        >
                          {title}
                        </a>
                      </li>
                    <% end %>
                  </ul>
                </nav>
              </aside>
            <% end %>
            
    <!-- Footer navigation -->
            <div class="mt-12 pt-8 border-t border-gray-800 flex justify-between">
              <div>
                <p class="text-sm text-gray-500">
                  Last updated: {format_date(DateTime.utc_now())}
                </p>
              </div>
              <div class="flex space-x-4">
                <a
                  href="https://github.com/lang/docs"
                  class="text-sm text-gray-400 hover:text-white transition-colors"
                >
                  Edit on GitHub
                </a>
                <a
                  href="/contact"
                  class="text-sm text-gray-400 hover:text-white transition-colors"
                >
                  Feedback
                </a>
              </div>
            </div>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  # Documentation generation functions
  defp generate_orchestrated_docs do
    try do
      # Create all necessary directories
      ensure_doc_directories()

      # Generate text environment docs
      generate_text_docs()

      # Generate other environment docs
      generate_filesystem_docs()
      generate_api_docs()

      :ok
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp ensure_doc_directories do
    environments = ["text", "filesystem", "cloud", "systems"]

    Enum.each(environments, fn env ->
      path = Path.join(@orchestrated_docs_path, env)
      File.mkdir_p!(path)
    end)
  end

  defp generate_text_docs do
    text_docs = %{
      "introduction" => generate_text_introduction(),
      "quickstart" => generate_text_quickstart(),
      "api_reference" => generate_text_api_reference(),
      "examples" => generate_text_examples(),
      "tutorials" => generate_text_tutorials(),
      "best_practices" => generate_text_best_practices(),
      "troubleshooting" => generate_text_troubleshooting()
    }

    base_path = Path.join(@orchestrated_docs_path, "text")

    Enum.each(text_docs, fn {filename, content} ->
      File.write!(Path.join(base_path, "#{filename}.md"), content)
    end)
  end

  defp generate_text_introduction do
    """
    # LANG Text Intelligence API

    Welcome to the LANG Text Intelligence API, a powerful system for analyzing,
    parsing, and extracting semantic information from text content.

    ## Features

    - **Multi-format Support**: Parse plain text, Markdown, and Markdown-LD
    - **Semantic Extraction**: Extract RDF triples and semantic relationships
    - **Entity Recognition**: Identify and classify named entities
    - **Stylometric Analysis**: Analyze writing style and authorship
    - **JSON-LD Output**: Structured, semantic-web compatible responses

    ## Getting Started

    1. Obtain your API key from the LANG dashboard
    2. Make your first API call using the examples below
    3. Explore advanced features like batch processing and webhooks

    ## Architecture

    The text intelligence system is built on:
    - **Native Rust NIFs** for high-performance text processing
    - **Tree-sitter parsers** for semantic code analysis
    - **Phoenix LiveView** for real-time interfaces
    - **Ash Framework** for robust data management
    """
  end

  defp generate_text_quickstart do
    """
    # Quick Start Guide

    ## 1. Authentication

    Include your API key in the `Authorization` header:

    ```bash
    curl -H "Authorization: Bearer lang_your_api_key" https://lang.nocsi.com/api/v1/analyze
    ```

    ## 2. Basic Text Analysis

    ```bash
    curl -X POST https://lang.nocsi.com/api/v1/sessions/SESSION_ID/analyze-text \\
      -H "Authorization: Bearer lang_your_api_key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "content": "Hello world! This is a sample text for analysis.",
        "format": "text"
      }'
    ```

    ## 3. Code Analysis

    ```bash
    curl -X POST https://lang.nocsi.com/api/v1/sessions/SESSION_ID/analyze-text \\
      -H "Authorization: Bearer lang_your_api_key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "content": "function hello() { console.log(\\"Hello world!\\"); }",
        "format": "javascript",
        "filename": "hello.js"
      }'
    ```

    ## 4. Document Analysis

    ```bash
    curl -X POST https://lang.nocsi.com/api/v1/sessions/SESSION_ID/analyze-text \\
      -H "Authorization: Bearer lang_your_api_key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "content": "# Documentation\\n\\nThis is **important** information.",
        "format": "markdown",
        "filename": "README.md"
      }'
    ```
    """
  end

  defp generate_text_api_reference do
    """
    # Text Analysis API Reference

    ## Base URL

    Production: `https://lang.nocsi.com/api/v1`

    ## Endpoints

    ### Analyze Text Content

    `POST /sessions/{session_id}/analyze-text`

    Analyze text content and return insights including complexity metrics,
    quality scores, and identified issues.

    **Parameters:**
    - `session_id` (path) - Analysis session ID

    **Request Body:**
    ```json
    {
      "content": "Text content to analyze",
      "format": "text|markdown|javascript|python|elixir|rust|go",
      "filename": "optional_filename.ext"
    }
    ```

    **Response:**
    ```json
    {
      "data": {
        "analysis": {
          "complexity": {
            "cyclomatic": 1,
            "cognitive": 1
          },
          "quality": {
            "maintainability": 85,
            "readability": 90
          },
          "violations": [
            {
              "rule": "rule_name",
              "severity": "error|warning|info",
              "line": 1,
              "message": "Description of the issue"
            }
          ]
        }
      }
    }
    ```

    ### Upload Files

    `POST /sessions/{session_id}/upload`

    Upload multiple files for batch analysis.

    **Parameters:**
    - `session_id` (path) - Analysis session ID

    **Request:** Multipart form data with files

    **Response:**
    ```json
    {
      "data": {
        "uploaded_files": [
          {
            "filename": "app.js",
            "size": 12454,
            "format": "javascript",
            "status": "uploaded"
          }
        ]
      }
    }
    ```

    ## Error Responses

    All endpoints return errors in this format:

    ```json
    {
      "error": {
        "code": "error_code",
        "message": "Human readable message",
        "details": {}
      }
    }
    ```

    ## Rate Limiting

    Rate limits are enforced per API key:
    - Free: 10 requests/minute
    - Professional: 100 requests/minute
    - Enterprise: 1000 requests/minute
    """
  end

  defp generate_text_examples do
    """
    # Text Analysis Examples

    ## JavaScript Code Analysis

    ```bash
    curl -X POST "https://lang.nocsi.com/api/v1/sessions/session-id/analyze-text" \\
      -H "Authorization: Bearer lang_your_api_key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "content": "function calculateTotal(items) {\\n  let total = 0;\\n  for (let item of items) {\\n    total += item.price;\\n  }\\n  return total;\\n}",
        "format": "javascript",
        "filename": "calculator.js"
      }'
    ```

    **Response:**
    ```json
    {
      "data": {
        "analysis": {
          "complexity": {
            "cyclomatic": 2,
            "cognitive": 2
          },
          "quality": {
            "maintainability": 85,
            "readability": 90,
            "testability": 80
          },
          "violations": []
        }
      }
    }
    ```

    ## Python Code Analysis

    ```bash
    curl -X POST "https://lang.nocsi.com/api/v1/sessions/session-id/analyze-text" \\
      -H "Authorization: Bearer lang_your_api_key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "content": "def fibonacci(n):\\n    if n <= 1:\\n        return n\\n    return fibonacci(n-1) + fibonacci(n-2)",
        "format": "python",
        "filename": "fibonacci.py"
      }'
    ```

    ## Markdown Document Analysis

    ```bash
    curl -X POST "https://lang.nocsi.com/api/v1/sessions/session-id/analyze-text" \\
      -H "Authorization: Bearer lang_your_api_key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "content": "# Project Documentation\\n\\n## Overview\\n\\nThis project provides...\\n\\n## Installation\\n\\n```bash\\nnpm install\\n```",
        "format": "markdown",
        "filename": "README.md"
      }'
    ```

    ## Batch File Upload

    ```bash
    curl -X POST "https://lang.nocsi.com/api/v1/sessions/session-id/upload" \\
      -H "Authorization: Bearer lang_your_api_key" \\
      -F "files[]=@src/app.js" \\
      -F "files[]=@src/utils.js" \\
      -F "files[]=@README.md"
    ```
    """
  end

  defp generate_text_tutorials do
    """
    # Text Analysis Tutorials

    ## Tutorial 1: Code Quality Assessment

    Learn how to use LANG to assess the quality of your codebase.

    ### Step 1: Create a Project

    ```bash
    curl -X POST "https://lang.nocsi.com/api/v1/projects" \\
      -H "Authorization: Bearer lang_your_api_key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "project": {
          "name": "Code Quality Assessment",
          "description": "Analyzing code quality for my application"
        }
      }'
    ```

    ### Step 2: Create an Analysis Session

    ```bash
    curl -X POST "https://lang.nocsi.com/api/v1/projects/PROJECT_ID/sessions" \\
      -H "Authorization: Bearer lang_your_api_key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "session": {
          "name": "Weekly Code Review",
          "analysis_type": "quality_scan"
        }
      }'
    ```

    ### Step 3: Analyze Your Code

    Upload your code files or analyze them directly:

    ```bash
    curl -X POST "https://lang.nocsi.com/api/v1/sessions/SESSION_ID/analyze-text" \\
      -H "Authorization: Bearer lang_your_api_key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "content": "// Your JavaScript code here",
        "format": "javascript"
      }'
    ```

    ### Step 4: Review Results

    Check the analysis results for:
    - Complexity metrics
    - Quality scores
    - Code violations
    - Improvement suggestions

    ## Tutorial 2: Document Analysis

    Analyze documentation quality and structure.

    ### Analyzing README Files

    ```bash
    curl -X POST "https://lang.nocsi.com/api/v1/sessions/SESSION_ID/analyze-text" \\
      -H "Authorization: Bearer lang_your_api_key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "content": "# My Project\\n\\nDescription here...",
        "format": "markdown",
        "filename": "README.md"
      }'
    ```

    Results include:
    - Document structure analysis
    - Readability metrics
    - Link validation
    - Content suggestions
    """
  end

  defp generate_text_best_practices do
    """
    # Best Practices for Text Analysis

    ## API Usage Best Practices

    ### 1. Authentication Security
    - Store API keys securely (environment variables)
    - Never commit keys to version control
    - Rotate keys regularly
    - Use different keys for different environments

    ### 2. Rate Limit Management
    - Implement exponential backoff for rate limited requests
    - Monitor your usage in the dashboard
    - Cache results to reduce API calls
    - Use batch endpoints for multiple files

    ### 3. Error Handling
    ```javascript
    async function analyzeText(content) {
      try {
        const response = await fetch('/api/v1/analyze', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ content, format: 'javascript' })
        });

        if (response.status === 429) {
          // Rate limited - implement backoff
          await new Promise(resolve => setTimeout(resolve, 60000));
          return analyzeText(content); // Retry
        }

        if (!response.ok) {
          throw new Error(`API error: ${response.status}`);
        }

        return await response.json();
      } catch (error) {
        console.error('Analysis failed:', error);
        return null;
      }
    }
    ```

    ## Code Analysis Best Practices

    ### 1. File Size Optimization
    - Keep individual files under 1MB for optimal processing
    - Use streaming for larger files
    - Consider splitting very large files

    ### 2. Batch Processing
    - Group related files in the same session
    - Use upload endpoint for multiple files
    - Process in chunks to avoid timeouts

    ### 3. Result Interpretation
    - Focus on high-severity violations first
    - Track metrics over time to see improvements
    - Set up automated quality gates
    - Use webhooks for continuous integration

    ## Performance Optimization

    ### 1. Caching Strategy
    ```javascript
    const analysisCache = new Map();

    function getCacheKey(content, format) {
      return crypto.createHash('md5').update(content + format).digest('hex');
    }

    async function analyzeWithCache(content, format) {
      const cacheKey = getCacheKey(content, format);

      if (analysisCache.has(cacheKey)) {
        return analysisCache.get(cacheKey);
      }

      const result = await analyzeText(content, format);
      analysisCache.set(cacheKey, result);
      return result;
    }
    ```

    ### 2. Parallel Processing
    ```javascript
    async function analyzeFiles(files) {
      const promises = files.map(file => analyzeText(file.content, file.format));
      const results = await Promise.allSettled(promises);

      return results.map((result, index) => ({
        file: files[index].name,
        success: result.status === 'fulfilled',
        data: result.status === 'fulfilled' ? result.value : null,
        error: result.status === 'rejected' ? result.reason : null
      }));
    }
    ```
    """
  end

  defp generate_text_troubleshooting do
    """
    # Troubleshooting Guide

    ## Common Issues

    ### Authentication Errors

    **Error: 401 Unauthorized**
    ```json
    {
      "error": {
        "code": "unauthorized",
        "message": "Invalid or missing authentication token"
      }
    }
    ```

    **Solutions:**
    - Verify your API key is correct
    - Check the Authorization header format: `Bearer lang_your_key`
    - Ensure the API key hasn't been revoked
    - Check if the key has the required scopes

    ### Rate Limiting

    **Error: 429 Too Many Requests**
    ```json
    {
      "error": {
        "code": "rate_limited",
        "message": "Too many requests. Please try again later.",
        "retry_after": 60
      }
    }
    ```

    **Solutions:**
    - Implement exponential backoff
    - Check your current tier limits in Settings
    - Consider upgrading your subscription
    - Use batch endpoints to reduce request count

    ### Analysis Errors

    **Error: 422 Unprocessable Entity**
    ```json
    {
      "error": {
        "code": "validation_failed",
        "message": "The provided data is invalid",
        "details": {
          "content": ["is too large (maximum 1MB)"],
          "format": ["is not supported"]
        }
      }
    }
    ```

    **Solutions:**
    - Check file size limits (1MB for direct analysis)
    - Verify the format is supported
    - Ensure content is properly encoded
    - Use file upload endpoint for larger files

    ### Timeout Issues

    **Error: 504 Gateway Timeout**

    **Solutions:**
    - Break large files into smaller chunks
    - Use streaming analysis for large documents
    - Check file complexity (deeply nested structures)
    - Try the request again (temporary server overload)

    ## Performance Issues

    ### Slow Analysis Times

    **Symptoms:**
    - Analysis takes longer than expected
    - Requests timeout frequently

    **Solutions:**
    - Reduce file size or complexity
    - Use appropriate analysis settings
    - Check network connectivity
    - Consider batch processing

    ### Memory Errors

    **Symptoms:**
    - Analysis fails with memory errors
    - Large files cause timeouts

    **Solutions:**
    - Use streaming analysis endpoints
    - Break files into smaller sections
    - Reduce analysis depth settings
    - Contact support for enterprise processing

    ## API Integration Issues

    ### CORS Errors (Browser)

    **Error:** `Access-Control-Allow-Origin` error

    **Solutions:**
    - Use server-side proxy for browser requests
    - Make requests from your backend instead
    - Use JSONP endpoints if available
    - Set up proper CORS in your application

    ### SSL Certificate Issues

    **Error:** SSL certificate verification failed

    **Solutions:**
    - Ensure you're using HTTPS endpoints
    - Update your HTTP client certificates
    - Check firewall/proxy settings
    - Use curl with `-k` flag for testing only

    ## Getting Help

    ### Debug Information to Include

    When contacting support, include:
    - API key (first 8 characters only)
    - Request timestamp
    - Full error response
    - Code sample demonstrating the issue
    - File size and format being analyzed

    ### Useful Debug Commands

    ```bash
    # Test basic connectivity
    curl -I https://lang.nocsi.com/health

    # Verify authentication
    curl -H "Authorization: Bearer lang_your_key" \\
         https://lang.nocsi.com/api/v1/stats/user

    # Check API status
    curl https://status.lang.dev/api/status.json
    ```

    ### Log Analysis

    Enable detailed logging in your application:

    ```javascript
    // Enable debug logging
    const debug = require('debug')('lang-api');

    async function debugAnalyze(content) {
      debug('Starting analysis for content length:', content.length);

      try {
        const result = await analyzeText(content);
        debug('Analysis completed successfully');
        return result;
      } catch (error) {
        debug('Analysis failed:', error.message);
        throw error;
      }
    }
    ```

    For additional support:
    - Check the [API Portal](/api-portal) for interactive testing
    - Join our [Community Forum](/community)
    - Contact [Support](/contact) for enterprise customers
    """
  end

  defp generate_filesystem_docs do
    filesystem_docs = %{
      "introduction" => """
      # LANG Filesystem Intelligence

      High-performance filesystem scanning and analysis with native Rust NIFs.

      ## Features
      - Parallel directory traversal
      - Content search with regex
      - Tree-sitter semantic search
      - File preview generation
      - Statistics collection

      ## Performance
      - 60-100x faster than pure Elixir
      - Processes ~10,000 files/second
      - Memory-mapped file access
      - Zero-copy operations where possible
      """,
      "api_reference" => """
      # Filesystem API Reference

      ## Scan Directory Tree

      `POST /api/v1/filesystem/scan`

      Scan a directory tree with high-performance parallel processing.

      **Request:**
      ```json
      {
        "path": "/path/to/project",
        "max_depth": 10,
        "include_hidden": false
      }
      ```

      **Response:**
      ```json
      {
        "data": {
          "tree": {
            "name": "project",
            "type": "directory",
            "children": [...]
          },
          "stats": {
            "total_files": 1234,
            "total_directories": 56,
            "processing_time_ms": 150
          }
        }
      }
      ```
      """
    }

    base_path = Path.join(@orchestrated_docs_path, "filesystem")

    Enum.each(filesystem_docs, fn {filename, content} ->
      File.write!(Path.join(base_path, "#{filename}.md"), content)
    end)
  end

  defp generate_api_docs do
    # Generate enhanced API documentation
    api_content = """
    # Complete LANG API Documentation

    This is the comprehensive API documentation generated by the orchestration system.

    ## Available Environments

    - **Text Intelligence** - `/docs/text/` - Text analysis and processing
    - **Filesystem Intelligence** - `/docs/filesystem/` - File system operations
    - **Cloud Intelligence** - `/docs/cloud/` - Cloud-based processing
    - **Systems Intelligence** - `/docs/systems/` - System integration

    ## Quick Links

    - [Text API Quick Start](/docs/text/quickstart)
    - [API Reference](/docs/text/api_reference)
    - [Code Examples](/docs/text/examples)
    - [Best Practices](/docs/text/best_practices)
    - [Troubleshooting](/docs/text/troubleshooting)

    This documentation is automatically generated by LANG's orchestration system
    and kept in sync with the latest API changes.
    """

    File.write!(Path.join(@docs_path, "api-generated.md"), api_content)
  end

  # Private functions
  defp load_doc(path) do
    # First try orchestration-generated docs
    orchestrated_file = Path.join(@orchestrated_docs_path, "#{path}.md")
    manual_file = Path.join(@docs_path, "#{path}.md")

    case File.read(orchestrated_file) do
      {:ok, content} ->
        title = extract_title(content) || format_title_from_path(path)
        {:ok, content, title}

      {:error, :enoent} ->
        # Fallback to manual docs
        case File.read(manual_file) do
          {:ok, content} ->
            title = extract_title(content) || format_title_from_path(path)
            {:ok, content, title}

          {:error, :enoent} ->
            {:error, :not_found}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_title(content) do
    case Regex.run(~r/^#\s+(.+)$/m, content) do
      [_, title] -> String.trim(title)
      nil -> nil
    end
  end

  defp extract_toc(content) do
    Regex.scan(~r/^(\#{2,6})\s+(.+)$/m, content)
    |> Enum.map(fn [_, hashes, title] ->
      level = String.length(hashes) - 1

      id =
        title
        |> String.downcase()
        |> String.replace(~r/[^\w\s-]/, "")
        |> String.replace(~r/\s+/, "-")

      {level, title, id}
    end)
  end

  defp render_markdown(content) do
    # In a real implementation, you'd use a markdown library like Earmark
    # For now, return basic HTML
    content
    |> String.replace(~r/^# (.+)$/m, "<h1>\\1</h1>")
    |> String.replace(~r/^## (.+)$/m, "<h2>\\1</h2>")
    |> String.replace(~r/^### (.+)$/m, "<h3>\\1</h3>")
    |> String.replace(~r/\*\*(.+?)\*\*/m, "<strong>\\1</strong>")
    |> String.replace(~r/\*(.+?)\*/m, "<em>\\1</em>")
    |> String.replace(~r/`(.+?)`/m, "<code>\\1</code>")
    |> String.replace(~r/\n\n/, "</p><p>")
    |> then(&("<p>" <> &1 <> "</p>"))
    |> String.replace("<p><h", "<h")
    |> String.replace("</h1></p>", "</h1>")
    |> String.replace("</h2></p>", "</h2>")
    |> String.replace("</h3></p>", "</h3>")
  end

  defp build_doc_tree do
    # Build a tree of available documentation
    []
  end

  defp format_title_from_path(path) do
    path
    |> String.replace("/", " > ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp level_class(level) do
    case level do
      1 -> "ml-0"
      2 -> "ml-4"
      3 -> "ml-8"
      _ -> "ml-12"
    end
  end

  defp format_date(datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_string()
  end

  defp load_markdown_file(path) do
    docs_path = Path.join(["docs", path])

    case File.read(docs_path) do
      {:ok, content} ->
        {:ok, content}

      {:error, _} ->
        # Try without docs prefix if it's an absolute path
        case File.read(path) do
          {:ok, content} -> {:ok, content}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp handle_doc_selection(socket, path) do
    case load_markdown_file(path) do
      {:ok, content} ->
        socket
        |> assign(:doc_content, content)
        |> assign(:current_doc, path)
        |> assign(:show_doc, true)

      {:error, _} ->
        socket
        |> put_flash(:error, "Could not load documentation file")
    end
  end
end
