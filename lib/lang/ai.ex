defmodule Lang.AI do
  @moduledoc """
  Simple, convenient interface for AI operations.

  This module provides a clean API for clients who just want to use AI
  capabilities without worrying about provider selection, routing, or
  implementation details.

  ## Examples

      # Just ask a question - system picks best provider
      Lang.AI.ask("What does this function do?", "def hello(name), do: ...")

      # Explain code intent
      Lang.AI.explain("lib/my_module.ex")

      # Generate code from description
      Lang.AI.generate("Create a function that validates email addresses")

      # Get security analysis
      Lang.AI.security_scan("lib/auth.ex")

      # Let Grok coordinate a complex mission
      Lang.AI.mission("Review this entire authentication system for problems")
  """

  alias Lang.Providers.Provider
  require Logger

  # =============================================================================
  # Simple Interface - Auto Provider Selection
  # =============================================================================

  @doc """
  Ask any AI question - system automatically picks the best provider
  """
  def ask(question, context \\ "", opts \\ []) do
    method = determine_method_from_question(question)

    params = %{
      query: question,
      context: context,
      content: context
    }

    case Provider.execute(method, params, opts) do
      {:ok, result} ->
        extract_simple_response(result)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Explain what code does - picks best explanation provider
  """
  def explain(file_path_or_content, opts \\ []) do
    params = %{
      content: normalize_content(file_path_or_content),
      context: Keyword.get(opts, :context, "general")
    }

    case Provider.execute("lang.think.explain_intent", params, opts) do
      {:ok, result} ->
        extract_simple_response(result)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Generate code from natural language description
  """
  def generate(description, opts \\ []) do
    params = %{
      specification: description,
      language: Keyword.get(opts, :language),
      framework: Keyword.get(opts, :framework)
    }

    # Force OpenAI for generation
    opts = Keyword.put(opts, :provider, :openai)

    case Provider.execute("lang.generate.from_spec", params, opts) do
      {:ok, result} ->
        extract_simple_response(result)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Security scan of code - always uses Claude
  """
  def security_scan(file_path_or_content, opts \\ []) do
    params = %{
      content: normalize_content(file_path_or_content),
      scan_type: Keyword.get(opts, :scan_type, "comprehensive")
    }

    # Force Anthropic for security
    opts = Keyword.put(opts, :provider, :anthropic)

    case Provider.execute("lang.think.security_scan", params, opts) do
      {:ok, result} ->
        extract_simple_response(result)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Diagnose errors and stack traces - always uses Claude
  """
  def diagnose(error_or_stacktrace, opts \\ []) do
    params = %{
      error_data: error_or_stacktrace,
      context: Keyword.get(opts, :context, %{})
    }

    # Force Anthropic for diagnostics
    opts = Keyword.put(opts, :provider, :anthropic)

    case Provider.execute("lang.think.diagnose", params, opts) do
      {:ok, result} ->
        extract_simple_response(result)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Complex mission coordination - always uses Grok commander
  """
  def mission(mission_description, opts \\ []) do
    Logger.info("Delegating complex mission", mission: mission_description)

    case Lang.Providers.Router.execute_mission(mission_description, opts) do
      {:ok, results} ->
        {:ok, format_mission_results(results)}

      {:error, error} ->
        {:error, error}
    end
  end

  # =============================================================================
  # Provider Control (for clients who care)
  # =============================================================================

  @doc """
  Talk directly to Grok
  """
  def grok(question, opts \\ []) do
    case Lang.Providers.XAI.analyze_situation("", question, opts) do
      {:ok, %{analysis: response}} -> {:ok, response}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Force use of specific provider
  """
  def with_provider(provider, method, params, opts \\ [])
      when provider in [:xai, :openai, :anthropic] do
    opts = Keyword.put(opts, :provider, provider)
    Provider.execute(method, params, opts)
  end

  # =============================================================================
  # Optimization Shortcuts
  # =============================================================================

  @doc """
  Cheapest option - uses Grok for everything it can handle
  """
  def cheap(question, context \\ "", opts \\ []) do
    opts = Keyword.put(opts, :provider, :xai)
    ask(question, context, opts)
  end

  @doc """
  Best quality - uses Claude/GPT-4 for everything
  """
  def best_quality(question, context \\ "", opts \\ []) do
    method = determine_method_from_question(question)

    provider =
      case method do
        method when method in ["lang.think.security_scan", "lang.think.diagnose"] -> :anthropic
        _ -> :openai
      end

    opts = Keyword.put(opts, :provider, provider)
    ask(question, context, opts)
  end

  @doc """
  Fastest option - picks fastest provider for each task
  """
  def fastest(question, context \\ "", opts \\ []) do
    method = determine_method_from_question(question)

    params = %{
      query: question,
      context: context,
      content: context
    }

    case Provider.select_provider(method, params, %{optimize_for: :speed}) do
      {:ok, provider} ->
        opts = Keyword.put(opts, :provider, provider)
        ask(question, context, opts)

      {:error, _} ->
        # fallback to auto
        ask(question, context, opts)
    end
  end

  # =============================================================================
  # Utility Functions
  # =============================================================================

  defp determine_method_from_question(question) do
    lower_question = String.downcase(question)

    cond do
      # Security-related questions
      String.contains?(lower_question, ["security", "vulnerability", "exploit", "attack", "hack"]) ->
        "lang.think.security_scan"

      # Code explanation
      String.contains?(lower_question, ["explain", "what does", "how does", "understand"]) ->
        "lang.think.explain_intent"

      # Bug prediction
      String.contains?(lower_question, ["bug", "error", "fail", "break", "wrong"]) ->
        "lang.think.predict_bugs"

      # Code generation
      String.contains?(lower_question, ["generate", "create", "write", "build", "make"]) ->
        "lang.generate.from_spec"

      # Diagnostic questions
      String.contains?(lower_question, ["debug", "trace", "diagnose", "why"]) ->
        "lang.think.diagnose"

      # Search questions
      String.contains?(lower_question, ["find", "search", "where", "show me"]) ->
        "lang.think.find_semantic"

      # Default to general explanation
      true ->
        "lang.think.explain_intent"
    end
  end

  defp normalize_content(content) when is_binary(content) do
    # If it looks like a file path, try to read it
    if String.contains?(content, "/") and File.exists?(content) do
      case File.read(content) do
        {:ok, file_content} -> file_content
        # Treat as direct content
        {:error, _} -> content
      end
    else
      content
    end
  end

  defp normalize_content(content), do: to_string(content)

  defp extract_simple_response(result) do
    case result do
      %{content: content} -> {:ok, content}
      %{analysis: analysis} -> {:ok, analysis}
      %{response: response} -> {:ok, response}
      content when is_binary(content) -> {:ok, content}
      other -> {:ok, inspect(other)}
    end
  end

  defp format_mission_results(%{
         results: results,
         successful_tasks: success_count,
         total_tasks: total
       }) do
    """
    Mission Results: #{success_count}/#{total} tasks completed successfully

    #{Enum.map_join(results, "\n\n", fn result -> case result do
        %{content: content} -> content
        %{analysis: analysis} -> analysis
        content when is_binary(content) -> content
        other -> inspect(other)
      end end)}
    """
  end

  # =============================================================================
  # Health and Status
  # =============================================================================

  @doc """
  Check if AI providers are healthy
  """
  def health_check do
    Provider.health_check_all()
  end

  @doc """
  Show what each provider is good at
  """
  def capabilities do
    Provider.capability_matrix()
  end

  @doc """
  Estimate cost before running expensive operations
  """
  def estimate_cost(method, params \\ %{}) do
    Provider.estimate_costs(method, params)
  end
end
