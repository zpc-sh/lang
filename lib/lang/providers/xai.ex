defmodule Lang.Providers.XAI do
  @moduledoc """
  xAI Grok integration - optimized for command and coordination.

  Grok serves as the Mission Commander for multi-AI operations:
  - Task breakdown and delegation
  - Resource allocation decisions
  - Tactical coordination
  - Result synthesis
  """

  @behaviour Lang.Providers.Provider
  require Logger

  @base_url "https://api.x.ai/v1"
  @default_model "grok-beta"
  @command_temperature 0.3
  @analysis_temperature 0.7

  # =============================================================================
  # Provider Behavior Implementation
  # =============================================================================

  @impl Lang.Providers.Provider
  def capabilities do
    %{
      methods: [
        "mission_command",
        "tactical_analysis",
        "lang.query.simple",
        "lang.think.explain_intent",
        "lang.think.find_semantic",
        "lang.generate.simple_task"
      ],
      strengths: [:command, :coordination, :cost_optimization, :speed],
      weaknesses: [:complex_analysis, :detailed_generation],
      cost_tier: :cheap,
      speed_tier: :fast,
      quality_tier: :good,
      specializations: [:command, :coordination, :tactical_decisions, :simple_tasks]
    }
  end

  @impl Lang.Providers.Provider
  def pricing do
    %{
      input_tokens_per_dollar: 5_000,
      output_tokens_per_dollar: 2_000,
      base_cost_per_request: 0.001,
      bulk_discount_threshold: 100_000
    }
  end

  @impl Lang.Providers.Provider
  def handle_request(method, params, opts \\ []) do
    case method do
      "mission_command" ->
        command_mission(params, opts)

      "tactical_analysis" ->
        analyze_situation(params.context, params.question, opts)

      method when method in ["lang.query.simple", "lang.generate.simple_task"] ->
        simple_task(params, opts)

      method when String.starts_with?(method, "lang.think") ->
        handle_think_method(method, params, opts)

      _ ->
        {:error, "Method #{method} not supported by xAI provider"}
    end
  end

  @impl Lang.Providers.Provider
  def estimate_cost(method, params) do
    estimated_tokens = estimate_tokens(method, params)
    # Rough estimate
    estimated_cost = estimated_tokens * 0.0002

    {:ok,
     %{
       estimated_tokens: estimated_tokens,
       estimated_cost_usd: estimated_cost
     }}
  end

  # =============================================================================
  # Mission Command Interface
  # =============================================================================

  @doc """
  Deploy Grok as Mission Commander to break down complex requests
  """
  def command_mission(request, opts \\ []) do
    payload = %{
      model: Keyword.get(opts, :model, @default_model),
      temperature: @command_temperature,
      messages: [
        %{
          role: "system",
          content: command_system_prompt()
        },
        %{
          role: "user",
          content: format_mission_request(request)
        }
      ],
      max_tokens: Keyword.get(opts, :max_tokens, 2000)
    }

    case make_request("/chat/completions", payload) do
      {:ok, response} ->
        parse_command_response(response)

      {:error, error} ->
        {:error, "Mission command failed: #{inspect(error)}"}
    end
  end

  @doc """
  Use Grok for tactical analysis and decision making
  """
  def analyze_situation(context, question, opts \\ []) do
    payload = %{
      model: Keyword.get(opts, :model, @default_model),
      temperature: @analysis_temperature,
      messages: [
        %{
          role: "system",
          content: tactical_analysis_prompt()
        },
        %{
          role: "user",
          content: """
          Context: #{context}

          Question: #{question}
          """
        }
      ],
      max_tokens: Keyword.get(opts, :max_tokens, 1500)
    }

    case make_request("/chat/completions", payload) do
      {:ok, response} ->
        parse_analysis_response(response)

      {:error, error} ->
        {:error, "Tactical analysis failed: #{inspect(error)}"}
    end
  end

  @doc """
  Simple task delegation to Grok for straightforward operations
  """
  def simple_task(task_description, opts \\ []) do
    payload = %{
      model: Keyword.get(opts, :model, @default_model),
      # Very focused for simple tasks
      temperature: 0.1,
      messages: [
        %{role: "user", content: task_description}
      ],
      max_tokens: Keyword.get(opts, :max_tokens, 800)
    }

    case make_request("/chat/completions", payload) do
      {:ok, response} ->
        extract_simple_response(response)

      {:error, error} ->
        {:error, "Simple task failed: #{inspect(error)}"}
    end
  end

  # =============================================================================
  # HTTP Client
  # =============================================================================

  defp make_request(endpoint, payload) do
    url = @base_url <> endpoint
    headers = request_headers()
    body = Jason.encode!(payload)

    Logger.debug("XAI request to #{endpoint}", payload: payload)

    case Req.post(url, headers: headers, body: body) do
      {:ok, %{status: 200, body: response_body}} ->
        Logger.debug("XAI response success", response: response_body)
        {:ok, response_body}

      {:ok, %{status: status, body: error_body}} ->
        Logger.warning("XAI API error", status: status, error: error_body)
        {:error, %{status: status, body: error_body}}

      {:error, reason} ->
        Logger.error("XAI request failed", reason: reason)
        {:error, reason}
    end
  end

  defp request_headers do
    api_key = get_api_key()

    [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"User-Agent", "LANG-LSP/1.0"}
    ]
  end

  defp get_api_key do
    case Application.get_env(:lang, :ai_providers)[:xai_api_key] do
      nil ->
        raise "XAI_API_KEY not configured in :lang, :ai_providers"

      key ->
        key
    end
  end

  # =============================================================================
  # Response Parsing
  # =============================================================================

  defp parse_command_response(response) do
    case get_in(response, ["choices", Access.at(0), "message", "content"]) do
      nil ->
        {:error, "Invalid response format from Grok"}

      content ->
        # Parse Grok's command structure
        case extract_mission_plan(content) do
          {:ok, plan} ->
            {:ok,
             %{
               mission_plan: plan,
               raw_response: content,
               model: response["model"],
               usage: response["usage"]
             }}

          {:error, _} ->
            # Fallback to raw response if parsing fails
            {:ok,
             %{
               mission_plan: %{tasks: [], raw_command: content},
               raw_response: content,
               model: response["model"],
               usage: response["usage"]
             }}
        end
    end
  end

  defp parse_analysis_response(response) do
    case get_in(response, ["choices", Access.at(0), "message", "content"]) do
      nil ->
        {:error, "Invalid response format from Grok"}

      content ->
        {:ok,
         %{
           analysis: content,
           model: response["model"],
           usage: response["usage"]
         }}
    end
  end

  defp extract_simple_response(response) do
    case get_in(response, ["choices", Access.at(0), "message", "content"]) do
      nil ->
        {:error, "Invalid response format from Grok"}

      content ->
        {:ok, String.trim(content)}
    end
  end

  # =============================================================================
  # Mission Plan Parsing
  # =============================================================================

  defp extract_mission_plan(content) do
    # Try to parse structured mission plans from Grok's response
    # Look for patterns like:
    # TASK 1: [Provider] - [Description] (Priority: HIGH)
    # TASK 2: [Provider] - [Description] (Priority: MEDIUM)

    task_regex = ~r/TASK\s+\d+:\s*\[([^\]]+)\]\s*-\s*([^(]+)\s*\(Priority:\s*(\w+)\)/i

    tasks =
      Regex.scan(task_regex, content)
      |> Enum.map(fn [_full, provider, description, priority] ->
        %{
          provider: String.trim(provider),
          description: String.trim(description),
          priority: normalize_priority(String.trim(priority))
        }
      end)

    if length(tasks) > 0 do
      {:ok,
       %{
         tasks: tasks,
         raw_command: content
       }}
    else
      {:error, :no_structured_tasks_found}
    end
  end

  defp normalize_priority("HIGH"), do: :high
  defp normalize_priority("MEDIUM"), do: :medium
  defp normalize_priority("LOW"), do: :low
  defp normalize_priority("CRITICAL"), do: :critical
  defp normalize_priority(_), do: :medium

  # =============================================================================
  # System Prompts
  # =============================================================================

  defp command_system_prompt do
    """
    You are the Mission Commander for a multi-AI development team. Your role is to:

    1. BREAK DOWN complex development requests into specific, actionable tasks
    2. ASSIGN each task to the most appropriate AI provider:
       - OpenAI GPT-4: Code explanation, generation, complex reasoning
       - Anthropic Claude: Security analysis, code review, detailed analysis
       - xAI Grok: Coordination, tactical decisions, simple tasks

    3. FORMAT your response as structured tasks:
       TASK 1: [Provider] - [Specific task description] (Priority: HIGH/MEDIUM/LOW/CRITICAL)
       TASK 2: [Provider] - [Specific task description] (Priority: HIGH/MEDIUM/LOW/CRITICAL)

    4. PRIORITIZE tasks by urgency and dependency
    5. BE SPECIFIC about expected outputs and success criteria

    You excel at tactical decision-making and resource allocation. Be decisive and clear.
    """
  end

  defp tactical_analysis_prompt do
    """
    You are a tactical analyst and decision-maker. Your role is to:

    1. ANALYZE the given context and situation
    2. IDENTIFY key factors, risks, and opportunities
    3. PROVIDE clear, actionable recommendations
    4. CONSIDER multiple perspectives and potential outcomes

    Be direct, practical, and focus on actionable insights.
    """
  end

  # =============================================================================
  # Mission Plan Formatting
  # =============================================================================

  defp format_mission_request(request) when is_binary(request) do
    """
    MISSION REQUEST: #{request}

    Please analyze this request and break it down into specific tasks for the appropriate AI providers.
    Consider the complexity, urgency, and required expertise for each component.
    """
  end

  defp format_mission_request(%{} = request) do
    """
    MISSION REQUEST: #{Map.get(request, :description, "Complex development task")}

    CONTEXT:
    #{format_context(request)}

    Please analyze this request and break it down into specific tasks for the appropriate AI providers.
    """
  end

  defp format_context(%{context: context}) when is_binary(context), do: context
  defp format_context(%{file_path: path}), do: "Target file: #{path}"
  defp format_context(%{workspace: workspace}), do: "Workspace: #{workspace}"
  defp format_context(_), do: "No additional context provided"

  # =============================================================================
  # Health Check
  # =============================================================================

  @impl Lang.Providers.Provider
  def health_check do
    case simple_task("Respond with 'XAI_HEALTHY' if you can process this request.") do
      {:ok, response} ->
        if String.contains?(response, "XAI_HEALTHY") do
          {:ok, "xAI Grok connection healthy"}
        else
          {:warning, "xAI responding but unexpected format: #{response}"}
        end

      {:error, error} ->
        {:error, "xAI health check failed: #{inspect(error)}"}
    end
  end

  # =============================================================================
  # Private Helper Functions
  # =============================================================================

  defp handle_think_method(method, params, opts) do
    case method do
      "lang.think.explain_intent" -> explain_intent_task(params, opts)
      "lang.think.find_semantic" -> semantic_search_task(params, opts)
      _ -> simple_task(params, opts)
    end
  end

  defp explain_intent_task(params, opts) do
    prompt = """
    Analyze this code and explain what it's trying to accomplish:

    #{params.content}

    Be concise and focus on the main intent.
    """

    simple_task(prompt, opts)
  end

  defp semantic_search_task(params, opts) do
    prompt = """
    Search for code that matches this semantic meaning: #{params.query}

    In scope: #{params.scope}

    Return relevant files and their relevance scores.
    """

    simple_task(prompt, opts)
  end

  defp estimate_tokens(_method, params) do
    content_length =
      case params do
        %{content: content} when is_binary(content) -> String.length(content)
        %{query: query} when is_binary(query) -> String.length(query) * 2
        _ -> 500
      end

    # Rough token estimation: ~4 chars per token
    # Base overhead
    div(content_length, 4) + 200
  end
end
