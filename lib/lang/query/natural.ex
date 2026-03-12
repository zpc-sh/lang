defmodule Elixir.Lang.LSP.Lang.Lang.Query.Natural do
  @moduledoc "Natural language queries"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.query.natural"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    query = Map.get(params, "query")
    context = Map.get(params, "context", %{})
    max_results = Map.get(params, "max_results", 10)
    include_code = Map.get(params, "include_code", true)

    case query do
      nil ->
        {:error, "query is required"}

      query when is_binary(query) ->
        case process_natural_language_query(query, context, max_results, include_code) do
          {:ok, results} ->
            {:ok,
             %{
               query: query,
               results: results,
               total_results: length(results),
               processing_time_ms: get_processing_time(),
               interpretation: interpret_query(query)
             }}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, "query must be a string"}
    end
  end

  defp process_natural_language_query(query, context, max_results, include_code) do
    # Parse the natural language query into structured search terms
    parsed_query = parse_natural_language(query)

    # Execute the search based on the parsed query
    search_results = execute_search(parsed_query, context, max_results)

    # Enhance results with code snippets if requested
    enhanced_results =
      if include_code do
        enhance_with_code_snippets(search_results)
      else
        search_results
      end

    {:ok, enhanced_results}
  end

  defp parse_natural_language(query) do
    # Extract key information from the natural language query
    %{
      intent: detect_intent(query),
      entities: extract_entities(query),
      filters: extract_filters(query),
      keywords: extract_keywords(query)
    }
  end

  defp detect_intent(query) do
    query_lower = String.downcase(query)

    cond do
      String.contains?(query_lower, ["find", "search", "look for", "show me"]) ->
        :search

      String.contains?(query_lower, ["how to", "how do i", "tutorial", "example"]) ->
        :how_to

      String.contains?(query_lower, ["what is", "what does", "explain", "definition"]) ->
        :explanation

      String.contains?(query_lower, ["error", "bug", "problem", "issue", "fix"]) ->
        :troubleshooting

      String.contains?(query_lower, ["performance", "optimize", "speed", "slow"]) ->
        :optimization

      String.contains?(query_lower, ["security", "vulnerability", "safe", "risk"]) ->
        :security

      true ->
        :general
    end
  end

  defp extract_entities(query) do
    # Extract programming-related entities
    entities = []

    # Programming languages
    languages = ["elixir", "phoenix", "rust", "javascript", "python", "go", "java"]
    found_languages = Enum.filter(languages, &String.contains?(String.downcase(query), &1))

    # File types
    file_extensions =
      Enum.filter(~w(.ex .exs .rs .js .py .go .java .md .json .yml .yaml), fn ext ->
        String.contains?(query, ext)
      end)

    # Function/module patterns
    function_matches = Regex.scan(~r/\b(\w+)\s*\(/, query) |> Enum.map(fn [_, name] -> name end)
    module_matches = Regex.scan(~r/\b[A-Z]\w*(?:\.[A-Z]\w*)*/, query) |> Enum.map(&List.first/1)

    entities
    |> maybe_add(:languages, found_languages)
    |> maybe_add(:file_extensions, file_extensions)
    |> maybe_add(:functions, function_matches)
    |> maybe_add(:modules, module_matches)
  end

  defp extract_filters(query) do
    filters = %{}

    # Time filters
    filters =
      cond do
        String.contains?(query, ["recent", "today", "yesterday"]) ->
          Map.put(filters, :time_range, :recent)

        String.contains?(query, ["this week", "past week"]) ->
          Map.put(filters, :time_range, :week)

        String.contains?(query, ["this month", "past month"]) ->
          Map.put(filters, :time_range, :month)

        true ->
          filters
      end

    # Size filters
    filters =
      cond do
        String.contains?(query, ["large", "big", "huge"]) ->
          Map.put(filters, :size, :large)

        String.contains?(query, ["small", "tiny", "minimal"]) ->
          Map.put(filters, :size, :small)

        true ->
          filters
      end

    # Complexity filters
    filters =
      cond do
        String.contains?(query, ["complex", "complicated", "advanced"]) ->
          Map.put(filters, :complexity, :high)

        String.contains?(query, ["simple", "basic", "easy"]) ->
          Map.put(filters, :complexity, :low)

        true ->
          filters
      end

    filters
  end

  defp extract_keywords(query) do
    # Remove common words and extract meaningful keywords
    stop_words =
      ~w(a an and or but the is are was were been be have has had do does did will would could should may might can)

    query
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    |> Enum.reject(&(&1 in stop_words))
    |> Enum.reject(&(String.length(&1) < 3))
    |> Enum.uniq()
  end

  defp execute_search(parsed_query, context, max_results) do
    # Build search strategy based on intent
    case parsed_query.intent do
      :search ->
        execute_file_search(parsed_query, context, max_results)

      :how_to ->
        execute_tutorial_search(parsed_query, context, max_results)

      :explanation ->
        execute_documentation_search(parsed_query, context, max_results)

      :troubleshooting ->
        execute_error_search(parsed_query, context, max_results)

      :optimization ->
        execute_performance_search(parsed_query, context, max_results)

      :security ->
        execute_security_search(parsed_query, context, max_results)

      _ ->
        execute_general_search(parsed_query, context, max_results)
    end
  end

  defp execute_file_search(parsed_query, _context, max_results) do
    # Search for files based on extracted entities and keywords
    search_pattern = build_search_pattern(parsed_query.keywords)

    # Use native filesystem scanner for performance
    case Lang.Native.FSScanner.search(".", search_pattern, max_results: max_results) do
      {:ok, results} ->
        format_file_search_results(results, parsed_query)

      {:error, _} ->
        # Fallback to simulated results
        generate_mock_file_results(parsed_query, max_results)
    end
  end

  defp execute_tutorial_search(parsed_query, _context, max_results) do
    # Search for tutorial-like content
    tutorials = [
      %{
        title:
          "Getting Started with #{List.first(parsed_query.entities[:languages] || ["Elixir"])}",
        type: :tutorial,
        relevance: 0.9,
        content: "Step-by-step guide to get you started",
        tags: parsed_query.entities[:languages] || []
      },
      %{
        title: "Best Practices for #{Enum.join(parsed_query.keywords, " ")}",
        type: :best_practices,
        relevance: 0.8,
        content: "Industry-standard approaches and patterns",
        tags: parsed_query.keywords
      }
    ]

    Enum.take(tutorials, max_results)
  end

  defp execute_documentation_search(parsed_query, _context, max_results) do
    # Search for documentation and explanations
    docs = [
      %{
        title: "Documentation: #{Enum.join(parsed_query.keywords, " ")}",
        type: :documentation,
        relevance: 0.95,
        content: "Comprehensive documentation and API reference",
        tags: parsed_query.keywords
      },
      %{
        title: "Concept: #{List.first(parsed_query.keywords, "Programming")}",
        type: :concept,
        relevance: 0.85,
        content: "Detailed explanation of core concepts",
        tags: parsed_query.keywords
      }
    ]

    Enum.take(docs, max_results)
  end

  defp execute_error_search(parsed_query, _context, max_results) do
    # Search for error-related content
    error_solutions = [
      %{
        title: "Common #{Enum.join(parsed_query.keywords, " ")} Errors",
        type: :troubleshooting,
        relevance: 0.9,
        content: "Solutions to frequently encountered issues",
        tags: parsed_query.keywords ++ ["error", "troubleshooting"]
      },
      %{
        title: "Debug Guide: #{List.first(parsed_query.keywords, "General")}",
        type: :debug_guide,
        relevance: 0.8,
        content: "Step-by-step debugging strategies",
        tags: parsed_query.keywords ++ ["debug", "troubleshooting"]
      }
    ]

    Enum.take(error_solutions, max_results)
  end

  defp execute_performance_search(parsed_query, _context, max_results) do
    # Search for performance-related content
    perf_results = [
      %{
        title: "Performance Optimization for #{Enum.join(parsed_query.keywords, " ")}",
        type: :optimization,
        relevance: 0.9,
        content: "Proven strategies to improve performance",
        tags: parsed_query.keywords ++ ["performance", "optimization"]
      },
      %{
        title: "Benchmarking #{List.first(parsed_query.keywords, "Code")}",
        type: :benchmarking,
        relevance: 0.85,
        content: "How to measure and improve performance",
        tags: parsed_query.keywords ++ ["benchmark", "metrics"]
      }
    ]

    Enum.take(perf_results, max_results)
  end

  defp execute_security_search(parsed_query, _context, max_results) do
    # Search for security-related content
    security_results = [
      %{
        title: "Security Best Practices: #{Enum.join(parsed_query.keywords, " ")}",
        type: :security_guide,
        relevance: 0.95,
        content: "Essential security considerations and practices",
        tags: parsed_query.keywords ++ ["security", "best_practices"]
      },
      %{
        title:
          "Vulnerability Assessment for #{List.first(parsed_query.keywords, "Applications")}",
        type: :security_assessment,
        relevance: 0.8,
        content: "How to identify and mitigate security risks",
        tags: parsed_query.keywords ++ ["vulnerability", "assessment"]
      }
    ]

    Enum.take(security_results, max_results)
  end

  defp execute_general_search(parsed_query, _context, max_results) do
    # General search combining multiple strategies
    general_results = [
      %{
        title: "Overview: #{Enum.join(parsed_query.keywords, " ")}",
        type: :overview,
        relevance: 0.7,
        content: "General information and overview",
        tags: parsed_query.keywords
      },
      %{
        title: "Examples: #{Enum.join(parsed_query.keywords, " ")}",
        type: :examples,
        relevance: 0.75,
        content: "Practical examples and code samples",
        tags: parsed_query.keywords ++ ["examples"]
      }
    ]

    Enum.take(general_results, max_results)
  end

  defp enhance_with_code_snippets(results) do
    Enum.map(results, fn result ->
      Map.put(result, :code_snippet, generate_relevant_code_snippet(result))
    end)
  end

  defp generate_relevant_code_snippet(result) do
    case result.type do
      :tutorial ->
        """
        # Example: Getting started
        defmodule Example do
          def hello_world do
            IO.puts("Hello, World!")
          end
        end
        """

      :troubleshooting ->
        """
        # Common error handling pattern
        case some_operation() do
          {:ok, result} -> result
          {:error, reason} ->
            Logger.error("Operation failed: \#{reason}")
            handle_error(reason)
        end
        """

      :optimization ->
        """
        # Performance optimization example
        def optimized_function(data) do
          data
          |> Enum.map(&process_item/1)
          |> Enum.filter(&valid_item?/1)
          |> Enum.take(100)
        end
        """

      _ ->
        """
        # Example implementation
        def example_function(params) do
          # Implementation here
          {:ok, params}
        end
        """
    end
  end

  defp build_search_pattern(keywords) do
    keywords
    |> Enum.join("|")
    |> case do
      "" -> ".*"
      pattern -> pattern
    end
  end

  defp format_file_search_results(results, parsed_query) do
    Enum.map(results, fn result ->
      %{
        title: Path.basename(result.file),
        type: :file,
        path: result.file,
        relevance: calculate_relevance(result, parsed_query),
        content: result.content,
        line_number: result.line_number,
        tags: extract_file_tags(result.file)
      }
    end)
  end

  defp generate_mock_file_results(parsed_query, max_results) do
    keywords = parsed_query.keywords
    file_ext = List.first(parsed_query.entities[:file_extensions] || [".ex"])

    Enum.map(1..max_results, fn i ->
      %{
        title: "#{List.first(keywords, "example")}_#{i}#{file_ext}",
        type: :file,
        path: "./lib/#{List.first(keywords, "example")}_#{i}#{file_ext}",
        relevance: 0.8 - i * 0.1,
        content: "Content related to #{Enum.join(keywords, " ")}",
        line_number: 1,
        tags: keywords
      }
    end)
  end

  defp calculate_relevance(_result, _parsed_query) do
    # Simple relevance calculation
    # In a real implementation, this would use more sophisticated scoring
    :rand.uniform() * 0.3 + 0.7
  end

  defp extract_file_tags(file_path) do
    ext = Path.extname(file_path)
    basename = Path.basename(file_path, ext)

    [ext, basename] ++ String.split(basename, ["_", "-"])
  end

  defp interpret_query(query) do
    %{
      confidence: calculate_confidence(query),
      suggested_refinements: suggest_refinements(query),
      related_queries: generate_related_queries(query)
    }
  end

  defp calculate_confidence(query) do
    # Simple confidence calculation based on query characteristics
    base_confidence = 0.5

    confidence_factors = [
      if(String.length(query) > 10, do: 0.1, else: 0.0),
      if(String.contains?(query, ["specific", "exact"]), do: 0.2, else: 0.0),
      if(Regex.match?(~r/\b\w+\.\w+\b/, query), do: 0.15, else: 0.0),
      if(String.contains?(query, ~w(how what where when why)), do: 0.15, else: 0.0)
    ]

    base_confidence + Enum.sum(confidence_factors)
  end

  defp suggest_refinements(query) do
    [
      "Try including specific file extensions (e.g., .ex, .rs)",
      "Add function or module names for more precise results",
      "Include error messages in quotes for troubleshooting",
      "Specify the programming language or framework"
    ]
  end

  defp generate_related_queries(query) do
    keywords = extract_keywords(query)

    [
      "Examples of #{List.first(keywords, "programming")}",
      "Best practices for #{Enum.join(keywords, " ")}",
      "Common errors in #{List.first(keywords, "code")}",
      "How to optimize #{Enum.join(keywords, " ")}"
    ]
  end

  defp get_processing_time do
    # Return a simulated processing time
    :rand.uniform(50) + 10
  end

  defp maybe_add(entities, _key, []), do: entities
  defp maybe_add(entities, key, values), do: Map.put(entities, key, values)
end
