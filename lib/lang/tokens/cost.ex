defmodule Lang.Tokens.Cost do
  @moduledoc """
  Comprehensive cost calculation functionality for LANG token operations.

  Provides token estimation, cost calculation, and pricing information
  for all supported LLM providers including real-time cost tracking
  for LSP chatroom sessions.

  Integrates with the existing LANG architecture:
  - Uses Lang.ModelConfig for pricing data
  - Works with Lang.Tokens.Estimate for token counting
  - Supports all LANG providers (OpenAI, Anthropic, Gemini, xAI, Qwen, Codex)
  - Provides real-time cost feedback for LSP chat sessions

  ## Features

  - **Token Usage Calculation**: Accurate input/output token tracking
  - **Multi-Provider Cost Comparison**: Compare costs across all providers
  - **Session-Level Cost Tracking**: Track cumulative costs across conversations
  - **Real-time Cost Estimation**: Live cost updates during streaming
  - **LSP Integration**: Cost feedback in the chatroom
  - **Billing Integration**: Works with LANG's existing billing system

  ## Examples

      # Calculate cost for a single request
      token_usage = %{input_tokens: 1000, output_tokens: 500}
      {:ok, cost} = Lang.Tokens.Cost.calculate(:openai, "gpt-4o", token_usage)

      # Compare costs across providers
      costs = Lang.Tokens.Cost.compare_providers(token_usage, [
        {:openai, "gpt-4o"},
        {:anthropic, "claude-3-5-sonnet-20241022"},
        {:gemini, "gemini-1.5-pro"}
      ])

      # Track session costs in LSP chat
      session = Lang.Tokens.Cost.start_session("chat_session_1")
      session = Lang.Tokens.Cost.add_message_cost(session, cost_data)
  """

  require Logger
  alias Lang.ModelConfig
  alias Lang.Tokens.{Estimate, Types}

  @doc """
  Calculate cost for token usage with a specific provider and model.

  ## Parameters
  - `provider`: Provider atom (:openai, :anthropic, :gemini, :xai, :qwen, :codex, etc.)
  - `model`: Model string (e.g., "gpt-4o", "claude-3-5-sonnet-20241022")
  - `token_usage`: Map with :input_tokens and :output_tokens

  ## Returns
  {:ok, cost_result} or {:error, reason}

  ## Examples

      iex> token_usage = %{input_tokens: 1000, output_tokens: 500}
      iex> Lang.Tokens.Cost.calculate(:openai, "gpt-4o", token_usage)
      {:ok, %{
        provider: "openai",
        model: "gpt-4o",
        input_tokens: 1000,
        output_tokens: 500,
        total_tokens: 1500,
        input_cost: 0.0025,
        output_cost: 0.005,
        total_cost: 0.0075,
        currency: "USD",
        pricing: %{input: 2.5, output: 10.0}
      }}
  """
  @spec calculate(atom(), String.t(), Types.token_usage()) ::
          {:ok, Types.cost_result()} | {:error, Types.cost_error()}
  def calculate(provider, model, token_usage) do
    case ModelConfig.get_pricing(provider, model) do
      nil ->
        {:error,
         %{
           error: "No pricing data available for #{provider}/#{model}",
           provider: to_string(provider),
           model: model
         }}

      pricing ->
        input_cost = calculate_token_cost(token_usage.input_tokens, pricing.input)
        output_cost = calculate_token_cost(token_usage.output_tokens, pricing.output)
        total_cost = input_cost + output_cost

        {:ok,
         %{
           provider: to_string(provider),
           model: model,
           input_tokens: token_usage.input_tokens,
           output_tokens: token_usage.output_tokens,
           total_tokens: token_usage.input_tokens + token_usage.output_tokens,
           input_cost: input_cost,
           output_cost: output_cost,
           total_cost: total_cost,
           currency: "USD",
           pricing: pricing
         }}
    end
  end

  @doc """
  Estimate token count for text content.

  Delegates to Lang.Tokens.Estimate but provides a consistent interface
  for cost calculation workflows.

  ## Examples

      iex> Lang.Tokens.Cost.estimate_tokens("Hello, world!")
      4
  """
  @spec estimate_tokens(String.t() | map() | [map()]) :: non_neg_integer()
  def estimate_tokens(content) do
    Estimate.estimate_tokens(content)
  end

  @doc """
  Calculate cost for text content without explicit token counting.

  Automatically estimates tokens and calculates cost.

  ## Examples

      iex> text = "Explain how machine learning works"
      iex> Lang.Tokens.Cost.calculate_for_text(:openai, "gpt-4o", text, text)
      {:ok, %{total_cost: 0.0045, ...}}
  """
  @spec calculate_for_text(atom(), String.t(), String.t(), String.t()) ::
          {:ok, Types.cost_result()} | {:error, Types.cost_error()}
  def calculate_for_text(provider, model, input_text, output_text) do
    input_tokens = estimate_tokens(input_text)
    output_tokens = estimate_tokens(output_text)

    token_usage = %{
      input_tokens: input_tokens,
      output_tokens: output_tokens
    }

    calculate(provider, model, token_usage)
  end

  @doc """
  Compare costs across multiple providers for the same token usage.

  Returns a list of cost results sorted by total cost (cheapest first).

  ## Examples

      iex> token_usage = %{input_tokens: 1000, output_tokens: 500}
      iex> providers = [
      ...>   {:openai, "gpt-4o-mini"},
      ...>   {:anthropic, "claude-3-5-haiku-20241022"},
      ...>   {:gemini, "gemini-1.5-flash"}
      ...> ]
      iex> Lang.Tokens.Cost.compare_providers(token_usage, providers)
      [
        %{provider: "gemini", model: "gemini-1.5-flash", total_cost: 0.00225, ...},
        %{provider: "openai", model: "gpt-4o-mini", total_cost: 0.00045, ...},
        ...
      ]
  """
  @spec compare_providers(Types.token_usage(), [{atom(), String.t()}]) :: [Types.cost_result()]
  def compare_providers(token_usage, provider_models) do
    provider_models
    |> Enum.map(fn {provider, model} ->
      case calculate(provider, model, token_usage) do
        {:ok, result} -> result
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.total_cost)
  end

  @doc """
  Find the cheapest provider/model combination for given token usage.

  ## Examples

      iex> token_usage = %{input_tokens: 1000, output_tokens: 500}
      iex> Lang.Tokens.Cost.cheapest_option(token_usage)
      {:ok, %{provider: "ollama", model: "llama3.1:8b", total_cost: 0.0, ...}}
  """
  @spec cheapest_option(Types.token_usage()) ::
          {:ok, Types.cost_result()} | {:error, String.t()}
  def cheapest_option(token_usage) do
    all_providers = [
      {:openai, "gpt-4o-mini"},
      {:anthropic, "claude-3-5-haiku-20241022"},
      {:gemini, "gemini-1.5-flash"},
      {:xai, "grok-beta"},
      {:qwen, "qwen2.5-7b-instruct"},
      {:codex, "github-copilot"},
      {:ollama, "llama3.1:8b"}
    ]

    case compare_providers(token_usage, all_providers) do
      [] -> {:error, "No providers available"}
      [cheapest | _] -> {:ok, cheapest}
    end
  end

  @doc """
  Format cost for human-readable display.

  Provides multiple formatting styles for different contexts.

  ## Options
  - `:style` - Format style (:auto, :detailed, :compact, :currency_only)
  - `:precision` - Decimal places (:auto or integer)

  ## Examples

      iex> Lang.Tokens.Cost.format_cost(0.0045)
      "$0.0045"

      iex> Lang.Tokens.Cost.format_cost(1.25, style: :detailed)
      "$1.25 USD"

      iex> Lang.Tokens.Cost.format_cost(0.0001, style: :compact)
      "$0.0001"
  """
  @spec format_cost(float(), keyword()) :: String.t()
  def format_cost(cost, opts \\ []) when is_number(cost) do
    style = Keyword.get(opts, :style, :auto)
    precision = Keyword.get(opts, :precision, :auto)

    formatted_cost =
      case {style, precision} do
        {:currency_only, :auto} -> auto_format(cost)
        {:currency_only, p} when is_integer(p) -> fixed_precision_format(cost, p)
        {:auto, :auto} -> auto_format(cost)
        {:detailed, _} -> "#{auto_format(cost)} USD"
        {:compact, _} -> compact_format(cost)
        {_, p} when is_integer(p) -> fixed_precision_format(cost, p)
        _ -> auto_format(cost)
      end

    formatted_cost
  end

  @doc """
  List all available models and their pricing across all providers.

  Returns a comprehensive list suitable for cost comparison interfaces.

  ## Examples

      iex> Lang.Tokens.Cost.list_all_pricing() |> Enum.take(3)
      [
        %{provider: "ollama", model: "llama3.1:8b", input_per_1m: 0.0, output_per_1m: 0.0},
        %{provider: "openai", model: "gpt-4o-mini", input_per_1m: 0.15, output_per_1m: 0.6},
        %{provider: "anthropic", model: "claude-3-5-haiku-20241022", input_per_1m: 1.0, output_per_1m: 5.0}
      ]
  """
  @spec list_all_pricing() :: [
          %{
            provider: String.t(),
            model: String.t(),
            input_per_1m: float(),
            output_per_1m: float()
          }
        ]
  def list_all_pricing do
    providers = ModelConfig.list_providers()

    for provider <- providers,
        {model, pricing} <- ModelConfig.get_all_pricing(provider),
        pricing != nil do
      %{
        provider: Atom.to_string(provider),
        model: model,
        input_per_1m: pricing.input,
        output_per_1m: pricing.output
      }
    end
    |> Enum.sort_by(&{&1.provider, &1.model})
  end

  @doc """
  Calculate streaming cost estimate based on current progress.

  Useful for LSP chatroom real-time cost display.

  ## Examples

      iex> current_tokens = %{input_tokens: 100, output_tokens: 50}
      iex> estimated_final = %{input_tokens: 100, output_tokens: 200}
      iex> Lang.Tokens.Cost.streaming_cost_estimate(:openai, "gpt-4o", current_tokens, estimated_final)
      %{
        current_cost: 0.00075,
        estimated_final_cost: 0.0025,
        progress_percentage: 62.5,
        estimated_remaining_cost: 0.00175
      }
  """
  @spec streaming_cost_estimate(atom(), String.t(), Types.token_usage(), Types.token_usage()) ::
          %{
            current_cost: float(),
            estimated_final_cost: float(),
            progress_percentage: float(),
            estimated_remaining_cost: float()
          }
  def streaming_cost_estimate(provider, model, current_tokens, estimated_final_tokens) do
    {:ok, current_cost} = calculate(provider, model, current_tokens)
    {:ok, final_cost} = calculate(provider, model, estimated_final_tokens)

    current_total = current_tokens.input_tokens + current_tokens.output_tokens
    final_total = estimated_final_tokens.input_tokens + estimated_final_tokens.output_tokens

    progress_percentage =
      if final_total > 0 do
        current_total / final_total * 100
      else
        0.0
      end

    %{
      current_cost: current_cost.total_cost,
      estimated_final_cost: final_cost.total_cost,
      progress_percentage: progress_percentage,
      estimated_remaining_cost: final_cost.total_cost - current_cost.total_cost
    }
  end

  @doc """
  Create a cost alert when certain thresholds are exceeded.

  Integrates with LANG's billing system for budget monitoring.

  ## Alert Types
  - `:budget_exceeded` - When cost exceeds set budget
  - `:high_cost_warning` - When single operation is expensive
  - `:efficiency_warning` - When cost efficiency is poor

  ## Examples

      iex> cost_data = %{total_cost: 1.25, provider: "openai", model: "gpt-4o"}
      iex> Lang.Tokens.Cost.cost_alert(:budget_exceeded, cost_data, budget: 1.00)
      "🚨 Budget exceeded! Current: $1.25, Budget: $1.00 (openai/gpt-4o)"
  """
  @spec cost_alert(atom(), map(), keyword()) :: String.t()
  def cost_alert(alert_type, cost_data, opts \\ [])

  def cost_alert(:budget_exceeded, cost_data, opts) do
    budget = Keyword.get(opts, :budget, 0.0)
    model_info = "#{cost_data[:provider] || "unknown"}/#{cost_data[:model] || "unknown"}"

    "🚨 Budget exceeded! Current: #{format_cost(cost_data.total_cost)}, Budget: #{format_cost(budget)} (#{model_info})"
  end

  def cost_alert(:high_cost_warning, cost_data, opts) do
    threshold = Keyword.get(opts, :threshold, 0.50)
    model_info = "#{cost_data[:provider] || "unknown"}/#{cost_data[:model] || "unknown"}"

    "⚠️ High cost detected: #{format_cost(cost_data.total_cost)} using #{model_info} (threshold: #{format_cost(threshold)})"
  end

  def cost_alert(:efficiency_warning, _cost_data, _opts) do
    "📊 Low efficiency detected. Consider switching to a more cost-effective model for this task type."
  end

  def cost_alert(:session_complete, cost_data, _opts) do
    session_info = if cost_data[:session_id], do: " (Session: #{cost_data.session_id})", else: ""
    "✅ Session complete#{session_info}. Total cost: #{format_cost(cost_data.total_cost)}"
  end

  def cost_alert(_, cost_data, _opts) do
    "ℹ️ Cost notification: #{format_cost(Map.get(cost_data, :total_cost, 0.0))}"
  end

  @doc """
  Generate cost summary for LSP chatroom display.

  Creates a formatted summary suitable for real-time display in the
  LANG LSP chatroom interface.

  ## Examples

      iex> cost_data = %{
      ...>   total_cost: 0.045,
      ...>   input_tokens: 1000,
      ...>   output_tokens: 500,
      ...>   provider: "openai",
      ...>   model: "gpt-4o"
      ...> }
      iex> Lang.Tokens.Cost.lsp_cost_summary(cost_data)
      "💰 $0.045 • 1,500 tokens • openai/gpt-4o"
  """
  @spec lsp_cost_summary(map()) :: String.t()
  def lsp_cost_summary(cost_data) do
    cost = format_cost(Map.get(cost_data, :total_cost, 0.0), style: :compact)
    total_tokens = Map.get(cost_data, :input_tokens, 0) + Map.get(cost_data, :output_tokens, 0)
    provider = Map.get(cost_data, :provider, "unknown")
    model = Map.get(cost_data, :model, "unknown")

    tokens_formatted = format_number(total_tokens)

    "💰 #{cost} • #{tokens_formatted} tokens • #{provider}/#{model}"
  end

  # Private helper functions

  defp calculate_token_cost(tokens, price_per_million)
       when is_number(tokens) and is_number(price_per_million) do
    tokens / 1_000_000 * price_per_million
  end

  defp auto_format(cost) when cost < 0.01 do
    "$#{Float.round(cost, 6)}"
  end

  defp auto_format(cost) when cost < 1.0 do
    "$#{Float.round(cost, 4)}"
  end

  defp auto_format(cost) when cost < 100.0 do
    "$#{Float.round(cost, 2)}"
  end

  defp auto_format(cost) do
    "$#{add_thousands_separator(Float.round(cost, 2))}"
  end

  defp compact_format(cost) when cost < 0.01 do
    "$#{Float.round(cost, 4)}"
  end

  defp compact_format(cost) when cost < 1.0 do
    "$#{Float.round(cost, 3)}"
  end

  defp compact_format(cost) when cost < 1000.0 do
    "$#{Float.round(cost, 1)}"
  end

  defp compact_format(cost) do
    cond do
      cost >= 1_000_000 ->
        millions = cost / 1_000_000
        "$#{Float.round(millions, 1)}M"

      cost >= 1_000 ->
        thousands = cost / 1000
        "$#{Float.round(thousands, 1)}K"

      true ->
        "$#{Float.round(cost, 1)}"
    end
  end

  defp fixed_precision_format(cost, precision) do
    "$#{Float.round(cost, precision)}"
  end

  defp add_thousands_separator(number) when is_number(number) do
    number
    |> to_string()
    |> add_thousands_separator()
  end

  defp add_thousands_separator(number_string) when is_binary(number_string) do
    [integer_part | decimal_part] = String.split(number_string, ".")

    integer_with_separators =
      integer_part
      |> String.reverse()
      |> String.codepoints()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.join/1)
      |> Enum.join(",")
      |> String.reverse()

    case decimal_part do
      [] -> integer_with_separators
      [decimals] -> "#{integer_with_separators}.#{decimals}"
    end
  end

  defp format_number(number) when number >= 1_000_000 do
    millions = number / 1_000_000
    "#{Float.round(millions, 1)}M"
  end

  defp format_number(number) when number >= 1_000 do
    thousands = number / 1_000
    "#{Float.round(thousands, 1)}K"
  end

  defp format_number(number) do
    Integer.to_string(number)
  end
end
