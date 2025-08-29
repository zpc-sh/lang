defmodule Lang.LSP.ChatCostIntegration do
  @moduledoc """
  Integration module for cost-aware chat functionality in the LANG LSP server.

  This module bridges the LSP chatroom with the cost calculation and batch processing
  systems, providing real-time cost feedback, budget monitoring, and intelligent
  provider selection directly in the LSP interface.

  ## Features

  - **Real-time Cost Tracking**: Live cost updates during chat sessions
  - **Budget Monitoring**: Proactive alerts when approaching cost limits
  - **Provider Optimization**: Automatic selection of cost-effective providers
  - **Batch Processing**: Efficient handling of multiple requests
  - **Cache Integration**: Leverages caching for cost savings
  - **Session Persistence**: Maintains cost state across LSP sessions

  ## LSP Methods

  This module handles the following LSP chat methods with cost integration:
  - `lang.chat.send_with_cost_tracking`
  - `lang.chat.get_session_cost_summary`
  - `lang.chat.set_budget_limit`
  - `lang.chat.optimize_provider_selection`
  - `lang.chat.batch_process_requests`

  ## Usage in LSP Client

      // Send message with cost tracking
      client.sendRequest('lang.chat.send_with_cost_tracking', {
        message: 'Explain machine learning',
        session_id: 'chat_123',
        cost_options: {
          limit: 0.50,
          real_time_updates: true,
          provider_optimization: 'cost_optimized'
        }
      });

      // Get cost summary
      client.sendRequest('lang.chat.get_session_cost_summary', {
        session_id: 'chat_123',
        format: 'detailed'
      });
  """

  require Logger
  alias Lang.LSP.Handler
  alias Lang.Conversation.{ChatBuilder, BatchProcessor}
  alias Lang.Tokens.{Cost, CostSession}
  alias Lang.Redis

  @behaviour Handler

  # LSP method handlers
  @lsp_methods [
    "lang.chat.send_with_cost_tracking",
    "lang.chat.get_session_cost_summary",
    "lang.chat.set_budget_limit",
    "lang.chat.optimize_provider_selection",
    "lang.chat.batch_process_requests",
    "lang.chat.estimate_request_cost",
    "lang.chat.get_cost_recommendations",
    "lang.chat.stream_with_cost_updates"
  ]

  @impl Handler
  def method, do: @lsp_methods

  @impl Handler
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    method = Map.get(params, "method", "lang.chat.send_with_cost_tracking")

    case method do
      "lang.chat.send_with_cost_tracking" -> handle_send_with_cost_tracking(params, ctx)
      "lang.chat.get_session_cost_summary" -> handle_get_session_cost_summary(params, ctx)
      "lang.chat.set_budget_limit" -> handle_set_budget_limit(params, ctx)
      "lang.chat.optimize_provider_selection" -> handle_optimize_provider_selection(params, ctx)
      "lang.chat.batch_process_requests" -> handle_batch_process_requests(params, ctx)
      "lang.chat.estimate_request_cost" -> handle_estimate_request_cost(params, ctx)
      "lang.chat.get_cost_recommendations" -> handle_get_cost_recommendations(params, ctx)
      "lang.chat.stream_with_cost_updates" -> handle_stream_with_cost_updates(params, ctx)
      _ -> {:error, "Unknown cost-aware chat method: #{method}"}
    end
  end

  # Send message with comprehensive cost tracking
  defp handle_send_with_cost_tracking(params, ctx) do
    message = Map.get(params, "message")
    session_id = Map.get(params, "session_id", generate_session_id())
    cost_options = Map.get(params, "cost_options", %{})
    provider = Map.get(params, "provider")
    model = Map.get(params, "model")

    case message do
      nil ->
        {:error, "message is required"}

      message when is_binary(message) ->
        # Build enhanced chat request with cost tracking
        builder_result = build_cost_aware_chat(message, session_id, cost_options, provider, model, ctx)

        case builder_result do
          {:ok, builder} ->
            case ChatBuilder.execute(builder) do
              {:ok, %{response: response, cost: cost_data, session: session}} ->
                # Send real-time cost update to LSP client
                send_cost_update_to_client(ctx, session_id, cost_data, session)

                # Format response with cost information
                formatted_response = format_cost_aware_response(response, cost_data, session)

                {:ok, formatted_response}

              {:error, reason} ->
                Logger.error("Cost-aware chat execution failed", reason: inspect(reason))
                {:error, "Chat processing failed: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, "message must be a string"}
    end
  end

  # Get comprehensive session cost summary
  defp handle_get_session_cost_summary(params, _ctx) do
    session_id = Map.get(params, "session_id")
    format = Map.get(params, "format", "detailed")

    case session_id do
      nil ->
        {:error, "session_id is required"}

      session_id ->
        case load_session(session_id) do
          {:ok, session} ->
            summary = CostSession.get_summary(session)
            formatted_summary = format_session_summary(summary, format)
            {:ok, formatted_summary}

          {:error, :not_found} ->
            {:error, "Session not found"}

          error ->
            error
        end
    end
  end

  # Set budget limit for session
  defp handle_set_budget_limit(params, _ctx) do
    session_id = Map.get(params, "session_id")
    budget_limit = Map.get(params, "budget_limit")
    alert_threshold = Map.get(params, "alert_threshold", 0.8)

    case {session_id, budget_limit} do
      {nil, _} ->
        {:error, "session_id is required"}

      {_, nil} ->
        {:error, "budget_limit is required"}

      {session_id, budget_limit} when is_number(budget_limit) and budget_limit > 0 ->
        case load_or_create_session(session_id, %{budget_limit: budget_limit}) do
          {:ok, session} ->
            updated_session = %{session | budget_limit: budget_limit}
            save_session(updated_session)

            # Check current budget status
            budget_status = CostSession.check_budget_status(updated_session)

            {:ok, %{
              session_id: session_id,
              budget_limit: budget_limit,
              current_cost: updated_session.total_cost,
              budget_status: budget_status,
              alert_threshold: alert_threshold
            }}

          error ->
            error
        end

      _ ->
        {:error, "budget_limit must be a positive number"}
    end
  end

  # Optimize provider selection based on cost or quality preferences
  defp handle_optimize_provider_selection(params, _ctx) do
    messages = Map.get(params, "messages", [])
    strategy = Map.get(params, "strategy", "cost_optimized")
    constraints = Map.get(params, "constraints", %{})

    case messages do
      [] ->
        {:error, "messages are required for provider optimization"}

      messages when is_list(messages) ->
        # Estimate costs across different providers
        providers_to_test = [
          {:openai, "gpt-4o-mini"},
          {:anthropic, "claude-3-5-haiku-20241022"},
          {:gemini, "gemini-1.5-flash"},
          {:xai, "grok-beta"}
        ]

        # Add local/free options if available
        providers_to_test = providers_to_test ++ [
          {:qwen, "qwen2.5-7b-instruct"},
          {:codex, "github-copilot"},
          {:ollama, "llama3.1:8b"}
        ]

        input_tokens = Cost.estimate_tokens(Jason.encode!(messages))
        estimated_output = Map.get(constraints, "estimated_output_tokens", 500)

        token_usage = %{input_tokens: input_tokens, output_tokens: estimated_output}

        cost_comparisons = Cost.compare_providers(token_usage, providers_to_test)

        # Apply strategy-based selection
        selected_provider = select_by_strategy(cost_comparisons, strategy, constraints)

        optimization_result = %{
          selected_provider: selected_provider,
          strategy: strategy,
          cost_comparisons: cost_comparisons,
          estimated_savings: calculate_estimated_savings(cost_comparisons, selected_provider),
          recommendations: generate_provider_recommendations(cost_comparisons, strategy)
        }

        {:ok, optimization_result}

      _ ->
        {:error, "messages must be a list"}
    end
  end

  # Handle batch processing of multiple requests with cost optimization
  defp handle_batch_process_requests(params, ctx) do
    requests = Map.get(params, "requests", [])
    batch_options = Map.get(params, "options", %{})
    session_id = Map.get(params, "session_id", generate_session_id())

    case requests do
      [] ->
        {:error, "requests array is required"}

      requests when is_list(requests) ->
        # Convert LSP requests to batch processor format
        processed_requests = Enum.map(requests, fn request ->
          %{
            messages: Map.get(request, "messages", []),
            provider: String.to_existing_atom(Map.get(request, "provider", "openai")),
            model: Map.get(request, "model", "gpt-4o-mini"),
            metadata: Map.merge(
              Map.get(request, "metadata", %{}),
              %{session_id: session_id, lsp_client: Map.get(ctx, "client_id")}
            )
          }
        end)

        # Configure batch processing with LSP integration
        processing_options = Map.merge(%{
          concurrency: Map.get(batch_options, "concurrency", 5),
          cost_limit: Map.get(batch_options, "cost_limit"),
          cache_enabled: Map.get(batch_options, "cache_enabled", true),
          progress_callback: create_lsp_progress_callback(ctx, session_id)
        }, batch_options)

        case BatchProcessor.process(processed_requests, processing_options) do
          {:ok, batch_result} ->
            # Update session with batch costs
            update_session_with_batch_result(session_id, batch_result)

            # Format result for LSP client
            lsp_result = format_batch_result_for_lsp(batch_result, session_id)

            {:ok, lsp_result}

          {:error, reason} ->
            Logger.error("Batch processing failed", reason: inspect(reason))
            {:error, "Batch processing failed: #{inspect(reason)}"}
        end

      _ ->
        {:error, "requests must be a list"}
    end
  end

  # Estimate cost before execution
  defp handle_estimate_request_cost(params, _ctx) do
    message = Map.get(params, "message")
    provider = Map.get(params, "provider", "openai")
    model = Map.get(params, "model", "gpt-4o-mini")
    estimated_output_tokens = Map.get(params, "estimated_output_tokens", 500)

    case message do
      nil ->
        {:error, "message is required"}

      message when is_binary(message) ->
        input_tokens = Cost.estimate_tokens(message)
        token_usage = %{input_tokens: input_tokens, output_tokens: estimated_output_tokens}

        provider_atom = String.to_existing_atom(provider)

        case Cost.calculate(provider_atom, model, token_usage) do
          {:ok, cost_data} ->
            estimate = %{
              provider: provider,
              model: model,
              input_tokens: input_tokens,
              estimated_output_tokens: estimated_output_tokens,
              estimated_cost: cost_data.total_cost,
              cost_breakdown: %{
                input_cost: cost_data.input_cost,
                output_cost: cost_data.output_cost
              },
              formatted_cost: Cost.format_cost(cost_data.total_cost),
              pricing_per_1m: cost_data.pricing
            }

            {:ok, estimate}

          {:error, error} ->
            {:error, "Cost estimation failed: #{inspect(error)}"}
        end

      _ ->
        {:error, "message must be a string"}
    end
  end

  # Get cost optimization recommendations
  defp handle_get_cost_recommendations(params, _ctx) do
    session_id = Map.get(params, "session_id")
    context = Map.get(params, "context", %{})

    case session_id do
      nil ->
        {:error, "session_id is required"}

      session_id ->
        case load_session(session_id) do
          {:ok, session} ->
            recommendations = CostSession.generate_cost_recommendations(session)

            enhanced_recommendations = %{
              session_recommendations: recommendations,
              general_recommendations: get_general_cost_recommendations(context),
              provider_alternatives: get_provider_alternatives(session),
              caching_opportunities: identify_caching_opportunities(session),
              budget_optimization: generate_budget_optimization_tips(session)
            }

            {:ok, enhanced_recommendations}

          {:error, :not_found} ->
            # Return general recommendations for new session
            {:ok, %{
              session_recommendations: [],
              general_recommendations: get_general_cost_recommendations(context),
              provider_alternatives: get_default_provider_alternatives(),
              caching_opportunities: [],
              budget_optimization: get_default_budget_tips()
            }}

          error ->
            error
        end
    end
  end

  # Stream with real-time cost updates
  defp handle_stream_with_cost_updates(params, ctx) do
    message = Map.get(params, "message")
    session_id = Map.get(params, "session_id", generate_session_id())
    cost_options = Map.get(params, "cost_options", %{})
    provider = Map.get(params, "provider")
    model = Map.get(params, "model")

    case message do
      nil ->
        {:error, "message is required"}

      message when is_binary(message) ->
        # Build streaming chat with cost tracking
        case build_cost_aware_chat(message, session_id, cost_options, provider, model, ctx) do
          {:ok, builder} ->
            # Set up streaming with cost updates
            stream_callback = create_cost_aware_stream_callback(ctx, session_id)

            case ChatBuilder.stream(builder, stream_callback) do
              :ok ->
                {:ok, %{
                  session_id: session_id,
                  streaming: true,
                  cost_tracking: true,
                  message: "Streaming started with real-time cost updates"
                }}

              {:error, reason} ->
                {:error, "Streaming failed: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, "message must be a string"}
    end
  end

  # Private helper functions

  defp build_cost_aware_chat(message, session_id, cost_options, provider, model, ctx) do
    try do
      # Create messages array
      messages = [%{role: "user", content: message}]

      # Build ChatBuilder with cost tracking
      builder =
        ChatBuilder.new()
        |> ChatBuilder.with_messages(messages)
        |> ChatBuilder.with_session_id(session_id)
        |> ChatBuilder.with_cost_tracking(
          limit: Map.get(cost_options, "limit"),
          session_tracking: Map.get(cost_options, "session_tracking", true),
          real_time_updates: Map.get(cost_options, "real_time_updates", true)
        )
        |> ChatBuilder.with_lsp_integration(port: 4001)
        |> ChatBuilder.with_cache(ttl: Map.get(cost_options, "cache_ttl", 3600))

      # Set provider if specified, otherwise use auto-selection
      builder = case {provider, model} do
        {nil, nil} ->
          strategy = Map.get(cost_options, "provider_optimization", "balanced")
          ChatBuilder.with_auto_provider_selection(builder, String.to_existing_atom(strategy))

        {provider, nil} when is_binary(provider) ->
          ChatBuilder.with_provider(builder, String.to_existing_atom(provider))

        {provider, model} when is_binary(provider) and is_binary(model) ->
          builder
          |> ChatBuilder.with_provider(String.to_existing_atom(provider))
          |> ChatBuilder.with_model(model)

        _ ->
          builder
      end

      # Add metadata from LSP context
      builder = ChatBuilder.with_metadata(builder, %{
        lsp_client_id: Map.get(ctx, "client_id"),
        user_id: Map.get(ctx, "user_id"),
        workspace: Map.get(ctx, "workspace_path")
      })

      {:ok, builder}
    rescue
      error ->
        Logger.error("Failed to build cost-aware chat", error: inspect(error))
        {:error, "Failed to configure chat request"}
    end
  end

  defp send_cost_update_to_client(ctx, session_id, cost_data, session) do
    client_id = Map.get(ctx, "client_id")

    if client_id do
      cost_update = %{
        type: "cost_update",
        session_id: session_id,
        current_message_cost: Cost.format_cost(cost_data.total_cost),
        session_total_cost: (if session, do: Cost.format_cost(session.total_cost), else: nil),
        token_usage: %{
          input_tokens: cost_data.input_tokens,
          output_tokens: cost_data.output_tokens,
          total_tokens: cost_data.total_tokens
        },
        provider: cost_data.provider,
        model: cost_data.model,
        timestamp: DateTime.utc_now()
      }

      # Send notification to LSP client
      Lang.LSP.Server.send_notification(client_id, "lang/cost_update", cost_update)
    end
  end

  defp format_cost_aware_response(response, cost_data, session) do
    base_response = %{
      content: extract_content_from_response(response),
      cost_info: %{
        message_cost: Cost.format_cost(cost_data.total_cost),
        token_usage: %{
          input_tokens: cost_data.input_tokens,
          output_tokens: cost_data.output_tokens,
          total_tokens: cost_data.total_tokens
        },
        provider: cost_data.provider,
        model: cost_data.model,
        cost_breakdown: %{
          input_cost: Cost.format_cost(cost_data.input_cost),
          output_cost: Cost.format_cost(cost_data.output_cost)
        }
      }
    }

    # Add session info if available
    if session do
      session_info = %{
        session_total_cost: Cost.format_cost(session.total_cost),
        message_count: session.message_count,
        budget_status: CostSession.check_budget_status(session)
      }

      Map.put(base_response, :session_info, session_info)
    else
      base_response
    end
  end

  defp format_session_summary(summary, format) do
    case format do
      "minimal" ->
        %{
          session_id: summary.session_id,
          total_cost: Cost.format_cost(summary.total_cost),
          message_count: summary.message_count,
          total_tokens: summary.total_tokens
        }

      "detailed" ->
        Map.merge(summary, %{
          formatted_total_cost: Cost.format_cost(summary.total_cost),
          formatted_avg_cost_per_message: Cost.format_cost(summary.average_cost_per_message),
          formatted_cost_per_1k_tokens: Cost.format_cost(summary.cost_per_1k_tokens),
          duration_formatted: format_duration(summary.duration),
          efficiency_percentage: round(summary.efficiency_score * 100)
        })

      "lsp" ->
        CostSession.format_for_lsp(%{
          session_id: summary.session_id,
          total_cost: summary.total_cost,
          message_count: summary.message_count,
          total_input_tokens: summary.input_tokens,
          total_output_tokens: summary.output_tokens,
          cost_alerts: summary.cost_alerts
        }, style: :detailed, show_alerts: true, show_recommendations: true)

      _ ->
        summary
    end
  end

  defp select_by_strategy(cost_comparisons, strategy, constraints) do
    case strategy do
      "cost_optimized" ->
        Enum.min_by(cost_comparisons, & &1.total_cost)

      "quality_optimized" ->
        # Prefer GPT-4 or Claude Sonnet for quality
        quality_preferred = ["gpt-4o", "claude-3-5-sonnet", "gemini-1.5-pro"]
        Enum.find(cost_comparisons, fn comp ->
          Enum.any?(quality_preferred, &String.contains?(comp.model, &1))
        end) || List.first(cost_comparisons)

      "speed_optimized" ->
        # Prefer faster models
        speed_preferred = ["gpt-4o-mini", "claude-3-5-haiku", "gemini-1.5-flash"]
        Enum.find(cost_comparisons, fn comp ->
          Enum.any?(speed_preferred, &String.contains?(comp.model, &1))
        end) || List.first(cost_comparisons)

      "local_preferred" ->
        # Prefer local/free models
        local_providers = ["ollama", "codex", "qwen"]
        Enum.find(cost_comparisons, fn comp ->
          comp.provider in local_providers
        end) || Enum.min_by(cost_comparisons, & &1.total_cost)

      _ ->
        # Balanced approach - consider cost vs quality
        sorted = Enum.sort_by(cost_comparisons, & &1.total_cost)
        # Take middle option for balance
        Enum.at(sorted, div(length(sorted), 2)) || List.first(sorted)
    end
  end

  defp calculate_estimated_savings(cost_comparisons, selected_provider) do
    if length(cost_comparisons) > 1 do
      max_cost = Enum.max_by(cost_comparisons, & &1.total_cost).total_cost
      savings = max_cost - selected_provider.total_cost
      savings_percentage = if max_cost > 0, do: savings / max_cost * 100, else: 0

      %{
        absolute_savings: Cost.format_cost(savings),
        percentage_savings: Float.round(savings_percentage, 1),
        compared_to_most_expensive: true
      }
    else
      %{absolute_savings: "$0.00", percentage_savings: 0, compared_to_most_expensive: false}
    end
  end

  defp generate_provider_recommendations(cost_comparisons, strategy) do
    recommendations = []

    # Cost-based recommendations
    recommendations = if length(cost_comparisons) > 1 do
      cheapest = Enum.min_by(cost_comparisons, & &1.total_cost)
      most_expensive = Enum.max_by(cost_comparisons, & &1.total_cost)

      cost_diff = most_expensive.total_cost - cheapest.total_cost

      if cost_diff > 0.01 do
        ["Consider #{cheapest.provider}/#{cheapest.model} for #{Float.round(cost_diff / most_expensive.total_cost * 100, 1)}% cost savings" | recommendations]
      else
        recommendations
      end
    else
      recommendations
    end

    # Strategy-specific recommendations
    recommendations = case strategy do
      "cost_optimized" ->
        ["Using most cost-effective option for budget optimization" | recommendations]

      "quality_optimized" ->
        ["Selected for higher quality output - consider cost-optimized for simple tasks" | recommendations]

      "local_preferred" ->
        ["Local models provide zero cost but may have quality trade-offs" | recommendations]

      _ ->
        recommendations
    end

    Enum.reverse(recommendations)
  end

  defp create_lsp_progress_callback(ctx, session_id) do
    client_id = Map.get(ctx, "client_id")

    fn progress ->
      if client_id do
        progress_update = %{
          type: "batch_progress",
          session_id: session_id,
          completed: progress.completed,
          total: progress.total,
          success_count: progress.success_count,
          error_count: progress.error_count,
          total_cost: Cost.format_cost(progress.total_cost),
          cache_hits: progress.cache_hits,
          progress_percentage: Map.get(progress, :progress_percentage, 0),
          estimated_remaining_time: Map.get(progress, :estimated_remaining_time),
          timestamp: DateTime.utc_now()
        }

        Lang.LSP.Server.send_notification(client_id, "lang/batch_progress", progress_update)
      end
    end
  end

  defp format_batch_result_for_lsp(batch_result, session_id) do
    %{
      session_id: session_id,
      success_count: batch_result.success_count,
      error_count: batch_result.error_count,
      total_cost: Cost.format_cost(batch_result.total_cost),
      processing_time_ms: batch_result.processing_time,
      cache_hits: batch_result.cache_hits,
      results: Enum.map(batch_result.results, &format_single_result_for_lsp/1),
      errors: batch_result.errors,
      metadata: %{
        cache_hit_rate: "#{batch_result.metadata.cache_hit_rate}%",
        average_cost_per_request: Cost.format_cost(batch_result.metadata.average_cost_per_request),
        requests_per_second: Float.round(batch_result.metadata.requests_per_second, 2),
        error_rate: "#{batch_result.metadata.error_rate}%"
      }
    }
  end

  defp format_single_result_for_lsp(result) do
    %{
      content: extract_content_from_response(Map.get(result, :response)),
      cost: (if Map.has_key?(result, :cost), do: Cost.format_cost(result.cost), else: nil),
      from_cache: Map.get(result, :from_cache, false),
      metadata: Map.get(result, :metadata, %{})
    }
  end

  defp create_cost_aware_stream_callback(ctx, session_id) do
    client_id = Map.get(ctx, "client_id")

    fn chunk ->
      enhanced_chunk = case chunk do
        %{content: content} = base_chunk ->
          # Add cost information to streaming chunk
          cost_info = Map.get(base_chunk, :cost_data, %{})

          %{
            type: "stream_chunk",
            session_id: session_id,
            content: content,
            cost_info: cost_info,
            timestamp: DateTime.utc_now()
          }

        %{type: :done} ->
          %{
            type: "stream_complete",
            session_id: session_id,
            timestamp: DateTime.utc_now()
          }

        other ->
          Map.merge(other, %{session_id: session_id, timestamp: DateTime.utc_now()})
      end

      if client_id do
        Lang.LSP.Server.send_notification(client_id, "lang/stream_update", enhanced_chunk)
      end
    end
  end

  # Session management helpers

  defp load_session(session_id) do
    case Redis.get("lang:session:#{session_id}") do
      {:ok, data} when data != nil ->
        {:ok, Jason.decode!(data, keys: :atoms)}
      _ ->
        {:error, :not_found}
    end
  end

  defp load_or_create_session(session_id, opts \\ %{}) do
    case load_session(session_id) do
      {:ok, session} -> {:ok, session}
      {:error, :not_found} ->
        session = CostSession.new(session_id, opts)
        save_session(session)
        {:ok, session}
    end
  end

  defp save_session(session) do
    data = Jason.encode!(session)
    Redis.setex("lang:session:#{session.session_id}", 7200, data)  # 2 hours TTL
  end

  defp update_session_with_batch_result(session_id, batch_result) do
    case load_or_create_session(session_id) do
      {:ok, session} ->
        # Add batch cost to session (simplified)
        updated_session = %{session | total_cost: session.total_cost + batch_result.total_cost}
        save_session(updated_session)

      _ -> :ok
    end
  end

  # Utility functions

  defp extract_content_from_response(response) do
    cond do
      is_binary(response) -> response
      is_map(response) -> Map.get(response, :content, Map.get(response, "content", ""))
      true -> ""
    end
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end
  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    remaining_minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{remaining_minutes}m"
  end

  defp generate_session_id do
    "lsp_cost_session_#{System.os_time(:millisecond)}"
  end

  defp get_general_cost_recommendations(_context) do
    [
      "Use gpt-4o-mini for simple queries (90% cost reduction vs GPT-4)",
      "Enable caching for repeated similar queries",
      "Consider local Ollama models for development/testing (free)",
      "Use batch processing for multiple requests",
      "Set budget limits to prevent unexpected costs"
    ]
  end

  defp get_provider_alternatives(session) do
    # Analyze session usage and suggest alternatives
    primary_provider = get_primary_provider_from_session(session)

    case primary_provider do
      "openai" ->
        [
          %{provider: "anthropic", model: "claude-3-5-haiku-20241022", savings: "~40%"},
          %{provider: "gemini", model: "gemini-1.5-flash", savings: "~60%"},
          %{provider: "ollama", model: "llama3.1:8b", savings: "100% (local)"}
        ]

      "anthropic" ->
        [
          %{provider: "openai", model: "gpt-4o-mini", savings: "~50%"},
          %{provider: "gemini", model: "gemini-1.5-flash", savings: "~60%"},
          %{provider: "ollama", model: "llama3.1:8b", savings: "100% (local)"}
        ]

      _ ->
        [
          %{provider: "openai", model: "gpt-4o-mini", savings: "varies"},
          %{provider: "ollama", model: "llama3.1:8b", savings: "100% (local)"}
        ]
    end
  end

  defp identify_caching_opportunities(session) do
    # Analyze message patterns for caching opportunities
    repeated_patterns = analyze_message_patterns(session)

    Enum.map(repeated_patterns, fn pattern ->
      %{
        pattern_type: pattern.type,
        occurrence_count: pattern.count,
        potential_savings: Cost.format_cost(pattern.estimated_savings),
        recommendation: pattern.recommendation
      }
    end)
  end

  defp generate_budget_optimization_tips(session) do
    tips = []

    # Budget-based tips
    tips = case session.budget_limit do
      nil ->
        ["Set a budget limit to track and control spending" | tips]

      budget when session.total_cost / budget > 0.8 ->
        ["You're using #{round(session.total_cost / budget * 100)}% of your budget - consider switching to cheaper models" | tips]

      _ -> tips
    end

    # Usage-based tips
    tips = if session.message_count > 10 and session.total_cost > 1.0 do
      ["Consider batch processing for multiple requests to reduce overhead" | tips]
    else
      tips
    end

    Enum.reverse(tips)
  end

  defp get_default_provider_alternatives do
    [
      %{provider: "ollama", model: "llama3.1:8b", savings: "100% (local)"},
      %{provider: "openai", model: "gpt-4o-mini", savings: "~80% vs GPT-4"},
      %{provider: "anthropic", model: "claude-3-5-haiku", savings: "~70% vs Claude Sonnet"},
      %{provider: "gemini", model: "gemini-1.5-flash", savings: "~60% vs premium models"}
    ]
  end

  defp get_default_budget_tips do
    [
      "Start with a $5 monthly budget for moderate usage",
      "Use gpt-4o-mini for most tasks (90% cheaper than GPT-4)",
      "Enable caching to reduce duplicate request costs",
      "Consider local models for development and testing"
    ]
  end

  defp get_primary_provider_from_session(session) do
    if Enum.empty?(session.provider_breakdown) do
      "openai"  # default
    else
      session.provider_breakdown
      |> Enum.max_by(fn {_provider, stats} -> stats.message_count end)
      |> elem(0)
    end
  end

  defp analyze_message_patterns(session) do
    # Simplified pattern analysis - in real implementation this would be more sophisticated
    messages = session.messages

    if length(messages) > 5 do
      [
        %{
          type: "similar_queries",
          count: 3,
          estimated_savings: 0.15,
          recommendation: "Enable caching for similar technical queries"
        }
      ]
    else
      []
    end
  end
end
