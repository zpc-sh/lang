defmodule Lang.Tokens.CostSession do
  @moduledoc """
  Session-level cost tracking and aggregation for LANG LSP chat sessions.

  Provides comprehensive cost tracking across entire conversation sessions,
  allowing users to monitor cumulative costs, analyze usage patterns,
  and get detailed breakdowns by provider, model, and message type.

  This module integrates directly with the LANG LSP chatroom to provide
  real-time cost feedback during conversations.

  ## Features

  - **Session Cost Aggregation**: Track total costs across all messages
  - **Provider/Model Breakdown**: See costs by provider and model
  - **Message-level Tracking**: Individual message cost history
  - **Real-time Updates**: Live cost updates during streaming responses
  - **Cost Efficiency Metrics**: Calculate average costs and efficiency
  - **Budget Monitoring**: Alert when approaching cost limits
  - **LSP Integration**: Seamless integration with chatroom interface

  ## Usage

      # Start a new chat session
      session = Lang.Tokens.CostSession.new("chat_session_1", %{
        user_id: "user_123",
        budget_limit: 5.00
      })

      # Add message costs as they occur
      session = session
        |> Lang.Tokens.CostSession.add_message_cost(message_cost_1)
        |> Lang.Tokens.CostSession.add_message_cost(message_cost_2)

      # Get session summary for display
      summary = Lang.Tokens.CostSession.get_summary(session)

      # Format for LSP chatroom display
      display_text = Lang.Tokens.CostSession.format_for_lsp(session)
  """

  require Logger
  alias Lang.Tokens.Cost

  defstruct [
    :session_id,
    :start_time,
    :user_id,
    :budget_limit,
    total_cost: 0.0,
    total_input_tokens: 0,
    total_output_tokens: 0,
    message_count: 0,
    messages: [],
    provider_breakdown: %{},
    model_breakdown: %{},
    cost_alerts: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          start_time: DateTime.t(),
          user_id: String.t() | nil,
          budget_limit: float() | nil,
          total_cost: float(),
          total_input_tokens: non_neg_integer(),
          total_output_tokens: non_neg_integer(),
          message_count: non_neg_integer(),
          messages: [message_cost_entry()],
          provider_breakdown: %{String.t() => provider_stats()},
          model_breakdown: %{String.t() => model_stats()},
          cost_alerts: [cost_alert()],
          metadata: map()
        }

  @type message_cost_entry :: %{
          timestamp: DateTime.t(),
          cost: float(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          model: String.t(),
          provider: String.t(),
          message_type: String.t(),
          message_id: String.t() | nil
        }

  @type provider_stats :: %{
          total_cost: float(),
          total_tokens: non_neg_integer(),
          message_count: non_neg_integer(),
          avg_cost_per_message: float(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @type model_stats :: %{
          total_cost: float(),
          total_tokens: non_neg_integer(),
          message_count: non_neg_integer(),
          provider: String.t(),
          avg_cost_per_message: float(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @type cost_alert :: %{
          type: atom(),
          message: String.t(),
          timestamp: DateTime.t(),
          cost: float(),
          threshold: float() | nil
        }

  @type session_summary :: %{
          session_id: String.t(),
          duration: non_neg_integer(),
          total_cost: float(),
          total_tokens: non_neg_integer(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          message_count: non_neg_integer(),
          average_cost_per_message: float(),
          cost_per_1k_tokens: float(),
          efficiency_score: float(),
          provider_breakdown: %{String.t() => provider_stats()},
          model_breakdown: %{String.t() => model_stats()},
          budget_utilization: float() | nil,
          cost_alerts: [cost_alert()],
          recommendations: [String.t()]
        }

  @doc """
  Initialize a new cost tracking session.

  ## Parameters
  - `session_id` - Unique identifier for the chat session
  - `opts` - Optional configuration including:
    - `:user_id` - User identifier for tracking
    - `:budget_limit` - Maximum cost limit for alerts
    - `:metadata` - Additional session metadata

  ## Examples

      iex> session = Lang.Tokens.CostSession.new("chat_123", %{
      ...>   user_id: "user_456",
      ...>   budget_limit: 2.50
      ...> })
      iex> session.session_id
      "chat_123"
      iex> session.total_cost
      0.0
  """
  @spec new(String.t(), map()) :: t()
  def new(session_id, opts \\ %{}) do
    %__MODULE__{
      session_id: session_id,
      start_time: DateTime.utc_now(),
      user_id: Map.get(opts, :user_id),
      budget_limit: Map.get(opts, :budget_limit),
      messages: [],
      metadata: Map.get(opts, :metadata, %{})
    }
  end

  @doc """
  Add a message cost to the session tracking.

  Updates all session metrics and checks for budget alerts.

  ## Parameters
  - `session` - Current session state
  - `cost_data` - Cost result from Lang.Tokens.Cost.calculate/3
  - `opts` - Optional message metadata including:
    - `:message_type` - Type of message ("user", "assistant", "system")
    - `:message_id` - Unique message identifier

  ## Examples

      cost_data = %{
        provider: "openai",
        model: "gpt-4o",
        total_cost: 0.025,
        input_tokens: 500,
        output_tokens: 300
      }

      session = Lang.Tokens.CostSession.add_message_cost(session, cost_data, %{
        message_type: "assistant",
        message_id: "msg_123"
      })
  """
  @spec add_message_cost(t(), map(), map()) :: t()
  def add_message_cost(session, cost_data, opts \\ %{}) do
    input_tokens = Map.get(cost_data, :input_tokens, 0)
    output_tokens = Map.get(cost_data, :output_tokens, 0)
    total_cost = Map.get(cost_data, :total_cost, 0.0)

    message_entry = %{
      timestamp: DateTime.utc_now(),
      cost: total_cost,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      model: Map.get(cost_data, :model, "unknown"),
      provider: Map.get(cost_data, :provider, "unknown"),
      message_type: Map.get(opts, :message_type, "unknown"),
      message_id: Map.get(opts, :message_id)
    }

    updated_session = %{
      session
      | total_cost: session.total_cost + total_cost,
        total_input_tokens: session.total_input_tokens + input_tokens,
        total_output_tokens: session.total_output_tokens + output_tokens,
        message_count: session.message_count + 1,
        messages: [message_entry | session.messages],
        provider_breakdown: update_provider_breakdown(session.provider_breakdown, message_entry),
        model_breakdown: update_model_breakdown(session.model_breakdown, message_entry)
    }

    # Check for budget alerts
    check_and_add_alerts(updated_session, total_cost)
  end

  @doc """
  Get comprehensive session summary with all metrics.

  ## Examples

      summary = Lang.Tokens.CostSession.get_summary(session)
      # => %{session_id: "chat_123", total_cost: 0.45, efficiency_score: 0.82, ...}
  """
  @spec get_summary(t()) :: session_summary()
  def get_summary(session) do
    duration = DateTime.diff(DateTime.utc_now(), session.start_time, :second)
    total_tokens = session.total_input_tokens + session.total_output_tokens

    %{
      session_id: session.session_id,
      duration: duration,
      total_cost: session.total_cost,
      total_tokens: total_tokens,
      input_tokens: session.total_input_tokens,
      output_tokens: session.total_output_tokens,
      message_count: session.message_count,
      average_cost_per_message: safe_divide(session.total_cost, session.message_count),
      cost_per_1k_tokens: calculate_cost_per_1k_tokens(session),
      efficiency_score: calculate_efficiency_score(session),
      provider_breakdown: session.provider_breakdown,
      model_breakdown: session.model_breakdown,
      budget_utilization: calculate_budget_utilization(session),
      cost_alerts: session.cost_alerts,
      recommendations: generate_recommendations(session)
    }
  end

  @doc """
  Format session summary for LSP chatroom display.

  Creates a concise, readable summary suitable for real-time display
  in the LANG LSP chatroom interface.

  ## Options
  - `:style` - Display style (:minimal, :detailed, :breakdown)
  - `:show_alerts` - Include cost alerts in display
  - `:show_recommendations` - Include optimization recommendations

  ## Examples

      # Minimal display
      Lang.Tokens.CostSession.format_for_lsp(session, style: :minimal)
      # => "💰 $0.045 • 5 msgs • 2.3K tokens"

      # Detailed display
      Lang.Tokens.CostSession.format_for_lsp(session, style: :detailed)
      # => "💰 Session Cost: $0.045 (5 messages, 2.3K tokens)\n🔥 Efficiency: 82% • 📊 Avg: $0.009/msg"
  """
  @spec format_for_lsp(t(), keyword()) :: String.t()
  def format_for_lsp(session, opts \\ []) do
    style = Keyword.get(opts, :style, :detailed)
    show_alerts = Keyword.get(opts, :show_alerts, true)
    show_recommendations = Keyword.get(opts, :show_recommendations, false)

    case style do
      :minimal -> format_minimal(session)
      :breakdown -> format_breakdown(session, show_alerts, show_recommendations)
      _ -> format_detailed(session, show_alerts, show_recommendations)
    end
  end

  @doc """
  Check if session is approaching or has exceeded budget limits.

  ## Examples

      iex> Lang.Tokens.CostSession.check_budget_status(session)
      {:ok, %{status: :within_budget, utilization: 45.2, remaining: 1.24}}

      iex> Lang.Tokens.CostSession.check_budget_status(over_budget_session)
      {:warning, %{status: :budget_exceeded, utilization: 120.5, exceeded_by: 0.51}}
  """
  @spec check_budget_status(t()) ::
          {:ok, map()} | {:warning, map()} | {:error, map()}
  def check_budget_status(session) do
    case session.budget_limit do
      nil ->
        {:ok, %{status: :no_budget_set, utilization: nil, remaining: nil}}

      budget when is_number(budget) and budget > 0 ->
        utilization = session.total_cost / budget * 100
        remaining = budget - session.total_cost

        cond do
          utilization >= 100.0 ->
            {:error,
             %{
               status: :budget_exceeded,
               utilization: Float.round(utilization, 1),
               exceeded_by: Float.round(-remaining, 4)
             }}

          utilization >= 80.0 ->
            {:warning,
             %{
               status: :approaching_budget,
               utilization: Float.round(utilization, 1),
               remaining: Float.round(remaining, 4)
             }}

          true ->
            {:ok,
             %{
               status: :within_budget,
               utilization: Float.round(utilization, 1),
               remaining: Float.round(remaining, 4)
             }}
        end

      _ ->
        {:error, %{status: :invalid_budget, utilization: nil, remaining: nil}}
    end
  end

  @doc """
  Get cost breakdown by provider with detailed statistics.

  ## Examples

      breakdown = Lang.Tokens.CostSession.provider_breakdown(session)
      # => [
      #   %{provider: "openai", total_cost: 0.025, message_count: 3, ...},
      #   %{provider: "anthropic", total_cost: 0.020, message_count: 2, ...}
      # ]
  """
  @spec provider_breakdown(t()) :: [map()]
  def provider_breakdown(session) do
    session.provider_breakdown
    |> Enum.map(fn {provider, stats} ->
      Map.put(stats, :provider, provider)
    end)
    |> Enum.sort_by(& &1.total_cost, :desc)
  end

  @doc """
  Get cost breakdown by model with detailed statistics.

  ## Examples

      breakdown = Lang.Tokens.CostSession.model_breakdown(session)
      # => [
      #   %{model: "gpt-4o", provider: "openai", total_cost: 0.025, ...},
      #   %{model: "claude-3-5-sonnet", provider: "anthropic", total_cost: 0.020, ...}
      # ]
  """
  @spec model_breakdown(t()) :: [map()]
  def model_breakdown(session) do
    session.model_breakdown
    |> Enum.map(fn {model, stats} ->
      Map.put(stats, :model, model)
    end)
    |> Enum.sort_by(& &1.total_cost, :desc)
  end

  @doc """
  Generate cost optimization recommendations based on session usage.

  Analyzes session patterns and suggests ways to reduce costs while
  maintaining quality.

  ## Examples

      recommendations = Lang.Tokens.CostSession.generate_cost_recommendations(session)
      # => [
      #   "Consider using gpt-4o-mini for simple queries (60% cost reduction)",
      #   "Switch to Claude Haiku for basic tasks (40% savings)",
      #   "Use local Ollama models for development/testing (100% cost reduction)"
      # ]
  """
  @spec generate_cost_recommendations(t()) :: [String.t()]
  def generate_cost_recommendations(session) do
    recommendations = []

    # Check if using expensive models for simple tasks
    recommendations =
      if using_expensive_models?(session) do
        [
          "Consider using cheaper models (gpt-4o-mini, Claude Haiku) for simple queries"
          | recommendations
        ]
      else
        recommendations
      end

    # Check for inefficient provider usage
    recommendations =
      if inefficient_provider_usage?(session) do
        cheapest = find_cheapest_alternative(session)
        ["Switch to #{cheapest} for better cost efficiency" | recommendations]
      else
        recommendations
      end

    # Suggest local models for development
    recommendations =
      if session.total_cost > 0.10 do
        ["Consider using local Ollama models for development/testing (free)" | recommendations]
      else
        recommendations
      end

    # Budget optimization
    recommendations =
      case session.budget_limit do
        nil ->
          ["Set a budget limit to track spending and get proactive alerts" | recommendations]

        budget when session.total_cost / budget > 0.5 ->
          [
            "You're using #{Float.round(session.total_cost / budget * 100, 1)}% of your budget - consider cost optimization"
            | recommendations
          ]

        _ ->
          recommendations
      end

    Enum.reverse(recommendations)
  end

  # Private helper functions

  defp update_provider_breakdown(breakdown, message_entry) do
    provider = message_entry.provider
    total_tokens = message_entry.input_tokens + message_entry.output_tokens

    Map.update(
      breakdown,
      provider,
      %{
        total_cost: message_entry.cost,
        total_tokens: total_tokens,
        message_count: 1,
        avg_cost_per_message: message_entry.cost,
        input_tokens: message_entry.input_tokens,
        output_tokens: message_entry.output_tokens
      },
      fn existing ->
        new_message_count = existing.message_count + 1

        %{
          total_cost: existing.total_cost + message_entry.cost,
          total_tokens: existing.total_tokens + total_tokens,
          message_count: new_message_count,
          avg_cost_per_message: (existing.total_cost + message_entry.cost) / new_message_count,
          input_tokens: existing.input_tokens + message_entry.input_tokens,
          output_tokens: existing.output_tokens + message_entry.output_tokens
        }
      end
    )
  end

  defp update_model_breakdown(breakdown, message_entry) do
    model = message_entry.model
    total_tokens = message_entry.input_tokens + message_entry.output_tokens

    Map.update(
      breakdown,
      model,
      %{
        total_cost: message_entry.cost,
        total_tokens: total_tokens,
        message_count: 1,
        provider: message_entry.provider,
        avg_cost_per_message: message_entry.cost,
        input_tokens: message_entry.input_tokens,
        output_tokens: message_entry.output_tokens
      },
      fn existing ->
        new_message_count = existing.message_count + 1

        %{
          total_cost: existing.total_cost + message_entry.cost,
          total_tokens: existing.total_tokens + total_tokens,
          message_count: new_message_count,
          provider: existing.provider,
          avg_cost_per_message: (existing.total_cost + message_entry.cost) / new_message_count,
          input_tokens: existing.input_tokens + message_entry.input_tokens,
          output_tokens: existing.output_tokens + message_entry.output_tokens
        }
      end
    )
  end

  defp check_and_add_alerts(session, message_cost) do
    alerts = []

    # Budget alerts
    alerts =
      case session.budget_limit do
        nil ->
          alerts

        budget when session.total_cost >= budget ->
          alert = %{
            type: :budget_exceeded,
            message:
              Cost.cost_alert(:budget_exceeded, %{current: session.total_cost, budget: budget}),
            timestamp: DateTime.utc_now(),
            cost: session.total_cost,
            threshold: budget
          }

          [alert | alerts]

        budget when session.total_cost >= budget * 0.8 ->
          alert = %{
            type: :budget_warning,
            message:
              "⚠️ Approaching budget limit: #{Cost.format_cost(session.total_cost)}/#{Cost.format_cost(budget)} (#{Float.round(session.total_cost / budget * 100, 1)}%)",
            timestamp: DateTime.utc_now(),
            cost: session.total_cost,
            threshold: budget * 0.8
          }

          [alert | alerts]

        _ ->
          alerts
      end

    # High single message cost alert
    alerts =
      if message_cost > 0.10 do
        alert = %{
          type: :high_message_cost,
          message: Cost.cost_alert(:high_cost_warning, %{cost: message_cost}),
          timestamp: DateTime.utc_now(),
          cost: message_cost,
          threshold: 0.10
        }

        [alert | alerts]
      else
        alerts
      end

    %{session | cost_alerts: alerts ++ session.cost_alerts}
  end

  defp safe_divide(_numerator, 0), do: 0.0
  defp safe_divide(numerator, denominator), do: numerator / denominator

  defp calculate_cost_per_1k_tokens(session) do
    total_tokens = session.total_input_tokens + session.total_output_tokens

    if total_tokens > 0 do
      session.total_cost / total_tokens * 1000
    else
      0.0
    end
  end

  defp calculate_efficiency_score(session) do
    # Calculate efficiency based on cost per token vs. market average
    # Higher score = more efficient (lower cost per token)
    if session.message_count == 0 do
      0.0
    else
      # Simplified efficiency calculation - could be more sophisticated
      avg_cost_per_message = session.total_cost / session.message_count
      # Rough market average per message
      market_avg = 0.02

      efficiency = max(0.0, min(1.0, 1.0 - (avg_cost_per_message - market_avg) / market_avg))
      Float.round(efficiency, 3)
    end
  end

  defp calculate_budget_utilization(session) do
    case session.budget_limit do
      nil -> nil
      budget when budget > 0 -> Float.round(session.total_cost / budget * 100, 1)
      _ -> nil
    end
  end

  defp generate_recommendations(session) do
    generate_cost_recommendations(session)
  end

  defp format_minimal(session) do
    total_tokens = session.total_input_tokens + session.total_output_tokens
    cost = Cost.format_cost(session.total_cost, style: :compact)
    tokens = format_number(total_tokens)

    "💰 #{cost} • #{session.message_count} msgs • #{tokens} tokens"
  end

  defp format_detailed(session, show_alerts, show_recommendations) do
    summary = get_summary(session)
    cost = Cost.format_cost(summary.total_cost)
    tokens = format_number(summary.total_tokens)
    efficiency = round(summary.efficiency_score * 100)
    avg_cost = Cost.format_cost(summary.average_cost_per_message, style: :compact)

    base_info =
      "💰 Session Cost: #{cost} (#{summary.message_count} messages, #{tokens} tokens)\n🔥 Efficiency: #{efficiency}% • 📊 Avg: #{avg_cost}/msg"

    # Add budget info if available
    budget_info =
      case summary.budget_utilization do
        nil -> ""
        util when util >= 100.0 -> "\n🚨 Budget exceeded! #{Float.round(util, 1)}% used"
        util when util >= 80.0 -> "\n⚠️ Budget: #{Float.round(util, 1)}% used"
        util -> "\n💚 Budget: #{Float.round(util, 1)}% used"
      end

    # Add alerts if requested
    alerts_info =
      if show_alerts and not Enum.empty?(session.cost_alerts) do
        recent_alerts = Enum.take(session.cost_alerts, 2)
        alert_text = Enum.map_join(recent_alerts, "\n", & &1.message)
        "\n#{alert_text}"
      else
        ""
      end

    # Add recommendations if requested
    recommendations_info =
      if show_recommendations do
        recommendations = Enum.take(summary.recommendations, 2)

        if not Enum.empty?(recommendations) do
          rec_text = Enum.map_join(recommendations, "\n💡 ", &"💡 #{&1}")
          "\n#{rec_text}"
        else
          ""
        end
      else
        ""
      end

    base_info <> budget_info <> alerts_info <> recommendations_info
  end

  defp format_breakdown(session, show_alerts, show_recommendations) do
    detailed = format_detailed(session, show_alerts, show_recommendations)

    # Add provider breakdown
    provider_breakdown =
      session
      |> provider_breakdown()
      |> Enum.take(3)
      |> Enum.map_join("\n", fn p ->
        cost = Cost.format_cost(p.total_cost, style: :compact)
        "  📍 #{p.provider}: #{cost} (#{p.message_count} msgs)"
      end)

    if provider_breakdown != "" do
      detailed <> "\n\nProvider Breakdown:\n" <> provider_breakdown
    else
      detailed
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

  defp using_expensive_models?(session) do
    # Check if predominantly using expensive models
    expensive_models = ["gpt-4", "gpt-4-turbo", "claude-3-opus", "claude-3-5-sonnet"]

    expensive_usage =
      session.model_breakdown
      |> Enum.filter(fn {model, _} ->
        Enum.any?(expensive_models, &String.contains?(model, &1))
      end)
      |> Enum.reduce(0.0, fn {_, stats}, acc -> acc + stats.total_cost end)

    expensive_usage / session.total_cost > 0.7
  end

  defp inefficient_provider_usage?(session) do
    # Simple check - could be more sophisticated
    session.total_cost > 0.05 and session.message_count > 5
  end

  defp find_cheapest_alternative(_session) do
    # Could analyze session patterns and suggest best alternative
    # For now, suggest general cheap options
    "gpt-4o-mini or Claude Haiku"
  end
end
