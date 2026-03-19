defmodule Lang.Conversation.ChatBuilder do
  @moduledoc """
  Builder-style API for LANG conversation operations with integrated cost tracking and batch processing.

  Provides a fluent interface for constructing chat requests with fine-grained control over:
  - Cost tracking and optimization
  - Batch processing for efficiency
  - Caching with Redis/storage backend
  - Provider selection and routing
  - Real-time streaming with cost feedback
  - LSP chatroom integration

  ## Basic Usage

      {:ok, response} =
        Lang.Conversation.ChatBuilder.new()
        |> with_messages([%{role: "user", content: "Hello!"}])
        |> with_provider(:openai)
        |> with_model("gpt-4o-mini")
        |> with_cost_tracking()
        |> execute()

  ## Advanced Pipeline with Cost Optimization

      {:ok, response} =
        Lang.Conversation.ChatBuilder.new()
        |> with_messages(messages)
        |> with_cost_limit(0.50)
        |> with_auto_provider_selection(:cost_optimized)
        |> with_cache(ttl: 3600)
        |> with_batch_processing(batch_size: 10)
        |> execute()

  ## LSP Chatroom Integration

      builder =
        Lang.Conversation.ChatBuilder.new()
        |> with_session_id("lsp_chat_123")
        |> with_lsp_integration()
        |> with_real_time_cost_updates()

      builder |> stream_to_lsp(fn chunk ->
        # Real-time cost updates sent to LSP client
        LSP.send_cost_update(chunk.cost_data)
        IO.write(chunk.content)
      end)

  ## Batch Processing

      requests = [
        %{messages: messages1, provider: :openai},
        %{messages: messages2, provider: :anthropic}
      ]

      {:ok, results} =
        Lang.Conversation.ChatBuilder.batch(requests)
        |> with_concurrent_limit(5)
        |> with_cost_tracking()
        |> execute_batch()
  """

  require Logger
  alias Lang.Tokens.{Cost, CostSession}
  alias Lang.ModelConfig
  alias Lang.Providers.{Provider, Router}
  alias Lang.Storage
  alias Lang.Conversation.Pipeline

  @type request_opts :: %{
          messages: [map()],
          provider: atom() | nil,
          model: String.t() | nil,
          session_id: String.t() | nil,
          options: map()
        }

  @type cost_opts :: %{
          enabled: boolean(),
          limit: float() | nil,
          session_tracking: boolean(),
          real_time_updates: boolean()
        }

  @type cache_opts :: %{
          enabled: boolean(),
          ttl: pos_integer() | :infinity,
          key_strategy: atom(),
          storage_backend: atom()
        }

  @type batch_opts :: %{
          enabled: boolean(),
          batch_size: pos_integer(),
          concurrent_limit: pos_integer(),
          timeout: pos_integer()
        }

  @type t :: %__MODULE__{
          request: request_opts(),
          cost_opts: cost_opts(),
          cache_opts: cache_opts(),
          batch_opts: batch_opts(),
          pipeline_mods: [tuple()],
          streaming: boolean(),
          lsp_integration: boolean(),
          metadata: map()
        }

  defstruct [
    request: %{
      messages: [],
      provider: nil,
      model: nil,
      session_id: nil,
      options: %{}
    },
    cost_opts: %{
      enabled: false,
      limit: nil,
      session_tracking: false,
      real_time_updates: false
    },
    cache_opts: %{
      enabled: false,
      ttl: 3600,
      key_strategy: :content_hash,
      storage_backend: :redis
    },
    batch_opts: %{
      enabled: false,
      batch_size: 5,
      concurrent_limit: 10,
      timeout: 30_000
    },
    pipeline_mods: [],
    streaming: false,
    lsp_integration: false,
    metadata: %{}
  ]

  # Construction and Basic Configuration

  @doc """
  Creates a new ChatBuilder instance.

  ## Examples

      builder = Lang.Conversation.ChatBuilder.new()
      builder = Lang.Conversation.ChatBuilder.new(%{session_id: "chat_123"})
  """
  @spec new(map()) :: t()
  def new(opts \\ %{}) do
    %__MODULE__{
      request: Map.merge(%{
        messages: [],
        provider: nil,
        model: nil,
        session_id: nil,
        options: %{}
      }, opts),
      metadata: %{
        created_at: DateTime.utc_now(),
        builder_id: generate_builder_id()
      }
    }
  end

  @doc """
  Creates a batch ChatBuilder for processing multiple requests.

  ## Examples

      requests = [
        %{messages: messages1, provider: :openai, model: "gpt-4o-mini"},
        %{messages: messages2, provider: :anthropic, model: "claude-3-5-haiku"}
      ]

      builder = Lang.Conversation.ChatBuilder.batch(requests)
  """
  @spec batch([request_opts()]) :: t()
  def batch(requests) when is_list(requests) do
    %__MODULE__{
      batch_opts: %{
        enabled: true,
        batch_size: length(requests),
        concurrent_limit: min(length(requests), 10),
        timeout: 30_000
      },
      metadata: %{
        created_at: DateTime.utc_now(),
        builder_id: generate_builder_id(),
        batch_requests: requests,
        batch_mode: true
      }
    }
  end

  # Message and Provider Configuration

  @doc """
  Sets the messages for the conversation.

  ## Examples

      builder |> with_messages([
        %{role: "system", content: "You are a helpful coding assistant"},
        %{role: "user", content: "Explain recursion"}
      ])
  """
  @spec with_messages(t(), [map()]) :: t()
  def with_messages(%__MODULE__{} = builder, messages) when is_list(messages) do
    put_in(builder.request.messages, messages)
  end

  @doc """
  Adds a single message to the conversation.

  ## Examples

      builder |> add_message(%{role: "user", content: "Hello!"})
      builder |> add_message(%{role: "assistant", content: "Hi there!"})
  """
  @spec add_message(t(), map()) :: t()
  def add_message(%__MODULE__{} = builder, message) when is_map(message) do
    current_messages = builder.request.messages
    put_in(builder.request.messages, current_messages ++ [message])
  end

  @doc """
  Sets the provider for the request.

  ## Examples

      builder |> with_provider(:openai)
      builder |> with_provider(:anthropic)
      builder |> with_provider(:gemini)
  """
  @spec with_provider(t(), atom()) :: t()
  def with_provider(%__MODULE__{} = builder, provider) when is_atom(provider) do
    put_in(builder.request.provider, provider)
  end

  @doc """
  Sets the model for the request.

  ## Examples

      builder |> with_model("gpt-4o")
      builder |> with_model("claude-3-5-sonnet-20241022")
      builder |> with_model("gemini-1.5-pro")
  """
  @spec with_model(t(), String.t()) :: t()
  def with_model(%__MODULE__{} = builder, model) when is_binary(model) do
    put_in(builder.request.model, model)
  end

  @doc """
  Automatically selects the best provider based on optimization strategy.

  ## Strategies
  - `:cost_optimized` - Choose cheapest option
  - `:quality_optimized` - Choose highest quality model
  - `:speed_optimized` - Choose fastest response
  - `:balanced` - Balance cost, quality, and speed

  ## Examples

      builder |> with_auto_provider_selection(:cost_optimized)
      builder |> with_auto_provider_selection(:quality_optimized)
  """
  @spec with_auto_provider_selection(t(), atom()) :: t()
  def with_auto_provider_selection(%__MODULE__{} = builder, strategy) do
    # Estimate tokens for provider selection
    estimated_tokens = estimate_request_tokens(builder.request.messages)

    case Provider.select_provider("lang.chat", %{tokens: estimated_tokens}, %{optimize_for: strategy}) do
      {:ok, selected_provider} ->
        builder
        |> put_in([:request, :provider], selected_provider)
        |> put_in([:metadata, :auto_selected], true)
        |> put_in([:metadata, :selection_strategy], strategy)

      {:error, _reason} ->
        # Fallback to default provider
        put_in(builder.request.provider, :openai)
    end
  end

  # Cost Tracking Configuration

  @doc """
  Enables cost tracking for the request.

  ## Examples

      builder |> with_cost_tracking()
      builder |> with_cost_tracking(limit: 1.00, session_tracking: true)
  """
  @spec with_cost_tracking(t(), keyword()) :: t()
  def with_cost_tracking(%__MODULE__{} = builder, opts \\ []) do
    cost_opts = %{
      enabled: true,
      limit: Keyword.get(opts, :limit),
      session_tracking: Keyword.get(opts, :session_tracking, false),
      real_time_updates: Keyword.get(opts, :real_time_updates, false)
    }

    %{builder | cost_opts: cost_opts}
  end

  @doc """
  Sets a cost limit for the request.

  ## Examples

      builder |> with_cost_limit(0.50)  # $0.50 maximum
      builder |> with_cost_limit(2.00)  # $2.00 maximum
  """
  @spec with_cost_limit(t(), float()) :: t()
  def with_cost_limit(%__MODULE__{} = builder, limit) when is_number(limit) do
    put_in(builder.cost_opts.limit, limit)
  end

  @doc """
  Enables session-level cost tracking.

  ## Examples

      builder |> with_session_cost_tracking()
      builder |> with_session_cost_tracking(budget: 5.00)
  """
  @spec with_session_cost_tracking(t(), keyword()) :: t()
  def with_session_cost_tracking(%__MODULE__{} = builder, opts \\ []) do
    session_id = builder.request.session_id || generate_session_id()
    budget = Keyword.get(opts, :budget)

    builder
    |> put_in([:request, :session_id], session_id)
    |> put_in([:cost_opts, :session_tracking], true)
    |> put_in([:cost_opts, :limit], budget)
  end

  @doc """
  Enables real-time cost updates during streaming.

  ## Examples

      builder |> with_real_time_cost_updates()
  """
  @spec with_real_time_cost_updates(t()) :: t()
  def with_real_time_cost_updates(%__MODULE__{} = builder) do
    builder
    |> put_in([:cost_opts, :real_time_updates], true)
    |> put_in([:cost_opts, :enabled], true)
  end

  # Caching Configuration

  @doc """
  Enables caching for the request.

  ## Examples

      builder |> with_cache()  # Default settings
      builder |> with_cache(ttl: 7200)  # 2 hours
      builder |> with_cache(ttl: :infinity, storage_backend: :s3)
  """
  @spec with_cache(t(), keyword()) :: t()
  def with_cache(%__MODULE__{} = builder, opts \\ []) do
    cache_opts = %{
      enabled: true,
      ttl: Keyword.get(opts, :ttl, 3600),
      key_strategy: Keyword.get(opts, :key_strategy, :content_hash),
      storage_backend: Keyword.get(opts, :storage_backend, :redis)
    }

    %{builder | cache_opts: cache_opts}
  end

  @doc """
  Disables caching for this request.

  ## Examples

      builder |> without_cache()
  """
  @spec without_cache(t()) :: t()
  def without_cache(%__MODULE__{} = builder) do
    put_in(builder.cache_opts.enabled, false)
  end

  # Batch Processing Configuration

  @doc """
  Enables batch processing with configurable options.

  ## Examples

      builder |> with_batch_processing()  # Default settings
      builder |> with_batch_processing(batch_size: 20, concurrent_limit: 5)
  """
  @spec with_batch_processing(t(), keyword()) :: t()
  def with_batch_processing(%__MODULE__{} = builder, opts \\ []) do
    batch_opts = %{
      enabled: true,
      batch_size: Keyword.get(opts, :batch_size, 10),
      concurrent_limit: Keyword.get(opts, :concurrent_limit, 5),
      timeout: Keyword.get(opts, :timeout, 30_000)
    }

    %{builder | batch_opts: batch_opts}
  end

  @doc """
  Sets concurrent processing limit for batch operations.

  ## Examples

      builder |> with_concurrent_limit(3)  # Max 3 concurrent requests
  """
  @spec with_concurrent_limit(t(), pos_integer()) :: t()
  def with_concurrent_limit(%__MODULE__{} = builder, limit) when is_integer(limit) and limit > 0 do
    put_in(builder.batch_opts.concurrent_limit, limit)
  end

  # LSP Integration

  @doc """
  Enables LSP chatroom integration.

  ## Examples

      builder |> with_lsp_integration()
      builder |> with_lsp_integration(port: 4001)
  """
  @spec with_lsp_integration(t(), keyword()) :: t()
  def with_lsp_integration(%__MODULE__{} = builder, opts \\ []) do
    port = Keyword.get(opts, :port, 4001)

    builder
    |> Map.put(:lsp_integration, true)
    |> put_in([:metadata, :lsp_port], port)
    |> put_in([:cost_opts, :real_time_updates], true)
  end

  @doc """
  Sets the session ID for LSP chatroom tracking.

  ## Examples

      builder |> with_session_id("lsp_chat_session_123")
  """
  @spec with_session_id(t(), String.t()) :: t()
  def with_session_id(%__MODULE__{} = builder, session_id) when is_binary(session_id) do
    put_in(builder.request.session_id, session_id)
  end

  # Advanced Configuration

  @doc """
  Sets request options like temperature, max_tokens, etc.

  ## Examples

      builder |> with_options(%{
        temperature: 0.7,
        max_tokens: 1000,
        top_p: 0.9
      })
  """
  @spec with_options(t(), map()) :: t()
  def with_options(%__MODULE__{} = builder, options) when is_map(options) do
    current_options = builder.request.options
    updated_options = Map.merge(current_options, options)
    put_in(builder.request.options, updated_options)
  end

  @doc """
  Adds metadata to the request.

  ## Examples

      builder |> with_metadata(%{user_id: "user_123", context: "code_review"})
  """
  @spec with_metadata(t(), map()) :: t()
  def with_metadata(%__MODULE__{} = builder, metadata) when is_map(metadata) do
    current_metadata = builder.metadata
    updated_metadata = Map.merge(current_metadata, metadata)
    %{builder | metadata: updated_metadata}
  end

  # Execution Methods

  @doc """
  Executes the chat request and returns the response with cost tracking.

  ## Returns
  - `{:ok, %{response: response, cost: cost_data, session: session}}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, %{response: response, cost: cost_data}} = builder |> execute()
  """
  @spec execute(t()) :: {:ok, map()} | {:error, term()}
  def execute(%__MODULE__{} = builder) do
    if builder.batch_opts.enabled and Map.has_key?(builder.metadata, :batch_requests) do
      execute_batch(builder)
    else
      execute_single(builder)
    end
  end

  @doc """
  Executes multiple requests in batch with cost tracking.

  ## Examples

      {:ok, results} = builder |> execute_batch()
  """
  @spec execute_batch(t()) :: {:ok, [map()]} | {:error, term()}
  def execute_batch(%__MODULE__{} = builder) do
    requests = Map.get(builder.metadata, :batch_requests, [])

    if Enum.empty?(requests) do
      {:error, :no_batch_requests}
    else
      process_batch_requests(builder, requests)
    end
  end

  @doc """
  Streams the response with real-time cost updates.

  ## Examples

      builder |> stream(fn chunk ->
        case chunk do
          %{type: :cost_update, cost: cost} ->
            IO.puts("Current cost: \#{Lang.Tokens.Cost.format_cost(cost)}")
          %{type: :content, content: content} ->
            IO.write(content)
          %{type: :done} ->
            IO.puts("\\nComplete!")
        end
      end)
  """
  @spec stream(t(), function()) :: :ok | {:error, term()}
  def stream(%__MODULE__{} = builder, callback) when is_function(callback, 1) do
    builder
    |> Map.put(:streaming, true)
    |> execute_stream(callback)
  end

  @doc """
  Streams directly to LSP client with integrated cost tracking.

  ## Examples

      builder |> stream_to_lsp(fn chunk ->
        Lang.LSP.Server.send_message(chunk)
      end)
  """
  @spec stream_to_lsp(t(), function()) :: :ok | {:error, term()}
  def stream_to_lsp(%__MODULE__{} = builder, callback) do
    builder
    |> with_lsp_integration()
    |> Map.put(:streaming, true)
    |> execute_stream_lsp(callback)
  end

  # Utility and Debugging

  @doc """
  Estimates the cost of the request before execution.

  ## Examples

      {:ok, estimate} = builder |> estimate_cost()
      # => %{estimated_cost: 0.0045, input_tokens: 150, output_tokens: 300}
  """
  @spec estimate_cost(t()) :: {:ok, map()} | {:error, term()}
  def estimate_cost(%__MODULE__{} = builder) do
    with {:ok, provider} <- get_effective_provider(builder),
         {:ok, model} <- get_effective_model(builder, provider) do

      input_tokens = estimate_request_tokens(builder.request.messages)
      # Rough estimate for output tokens
      output_tokens = Map.get(builder.request.options, :max_tokens, 500)

      token_usage = %{input_tokens: input_tokens, output_tokens: output_tokens}

      case Cost.calculate(provider, model, token_usage) do
        {:ok, cost_data} ->
          {:ok, %{
            estimated_cost: cost_data.total_cost,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            provider: provider,
            model: model
          }}

        error -> error
      end
    end
  end

  @doc """
  Returns detailed information about the builder configuration.

  ## Examples

      info = builder |> debug_info()
  """
  @spec debug_info(t()) :: map()
  def debug_info(%__MODULE__{} = builder) do
    %{
      request: builder.request,
      cost_tracking: builder.cost_opts,
      caching: builder.cache_opts,
      batch_processing: builder.batch_opts,
      lsp_integration: builder.lsp_integration,
      streaming: builder.streaming,
      metadata: builder.metadata,
      estimated_cost: case estimate_cost(builder) do
        {:ok, estimate} -> estimate
        {:error, _} -> :unavailable
      end
    }
  end

  # Private Implementation Functions

  defp execute_single(builder) do
    with {:ok, provider} <- get_effective_provider(builder),
         {:ok, model} <- get_effective_model(builder, provider) do

      # Check cost limits before execution
      if builder.cost_opts.enabled do
        case check_cost_limits(builder, provider, model) do
          :ok -> proceed_with_execution(builder, provider, model)
          {:error, reason} -> {:error, reason}
        end
      else
        proceed_with_execution(builder, provider, model)
      end
    end
  end

  defp proceed_with_execution(builder, provider, model) do
    # Check cache first
    cache_result = if builder.cache_opts.enabled do
      check_cache(builder, provider, model)
    else
      nil
    end

    case cache_result do
      {:hit, cached_response} ->
        Logger.debug("Cache hit for request")
        {:ok, cached_response}

      _ ->
        # Execute request
        execute_request(builder, provider, model)
    end
  end

  defp execute_request(builder, provider, model) do
    # Initialize cost session if needed
    session = if builder.cost_opts.session_tracking do
      case builder.request.session_id do
        nil -> nil
        session_id ->
          CostSession.new(session_id, %{
            budget_limit: builder.cost_opts.limit
          })
      end
    else
      nil
    end

    # Execute the actual request
    request_params = %{
      messages: builder.request.messages,
      model: model,
      options: builder.request.options
    }

    case Provider.execute("lang.chat", request_params, provider: provider) do
      {:ok, response} ->
        # Calculate cost
        cost_data = if builder.cost_opts.enabled do
          calculate_response_cost(response, provider, model)
        else
          nil
        end

        # Update session if tracking
        updated_session = if session && cost_data do
          CostSession.add_message_cost(session, cost_data)
        else
          session
        end

        # Cache response if enabled
        if builder.cache_opts.enabled && cost_data do
          cache_response(builder, provider, model, response, cost_data)
        end

        result = %{
          response: response,
          cost: cost_data,
          session: updated_session,
          metadata: builder.metadata
        }

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_batch_requests(builder, requests) do
    # Process requests in batches with concurrency limits
    requests
    |> Enum.chunk_every(builder.batch_opts.batch_size)
    |> Enum.reduce({:ok, []}, fn batch, {:ok, acc_results} ->
      batch_result = process_batch_chunk(builder, batch)
      case batch_result do
        {:ok, batch_results} -> {:ok, acc_results ++ batch_results}
        error -> error
      end
    end)
  end

  defp process_batch_chunk(builder, batch_requests) do
    # Execute requests concurrently with limits
    Task.async_stream(
      batch_requests,
      fn request ->
        request_builder =
          builder
          |> with_messages(request.messages)
          |> with_provider(request[:provider] || builder.request.provider)
          |> with_model(request[:model] || builder.request.model)

        execute_single(request_builder)
      end,
      max_concurrency: builder.batch_opts.concurrent_limit,
      timeout: builder.batch_opts.timeout
    )
    |> Enum.reduce({:ok, []}, fn
      {:ok, {:ok, result}}, {:ok, acc} -> {:ok, [result | acc]}
      {:ok, {:error, reason}}, _ -> {:error, reason}
      {:exit, reason}, _ -> {:error, {:timeout_or_exit, reason}}
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  defp execute_stream(builder, callback) do
    with {:ok, provider} <- get_effective_provider(builder),
         {:ok, model} <- get_effective_model(builder, provider) do

      # Set up streaming options
      streaming_options = Map.merge(builder.request.options, %{
        stream: true,
        stream_callback: create_streaming_callback(builder, callback)
      })

      request_params = %{
        messages: builder.request.messages,
        model: model,
        options: streaming_options
      }

      Provider.execute("lang.chat", request_params, provider: provider)
    end
  end

  defp execute_stream_lsp(builder, callback) do
    execute_stream(builder, fn chunk ->
      # Add LSP-specific formatting
      lsp_chunk = case chunk do
        %{content: content} = base_chunk ->
          Map.merge(base_chunk, %{
            type: :lsp_content,
            session_id: builder.request.session_id,
            timestamp: DateTime.utc_now()
          })

        other -> other
      end

      callback.(lsp_chunk)
    end)
  end

  defp create_streaming_callback(builder, user_callback) do
    # Initialize cost tracking state
    cost_state = %{
      current_tokens: %{input_tokens: 0, output_tokens: 0},
      session: if builder.cost_opts.session_tracking do
        session_id = builder.request.session_id || generate_session_id()
        CostSession.new(session_id, %{budget_limit: builder.cost_opts.limit})
      else
        nil
      end
    }

    fn chunk ->
      # Update cost tracking if enabled
      updated_state = if builder.cost_opts.real_time_updates do
        update_streaming_cost(cost_state, chunk, builder)
      else
        cost_state
      end

      # Add cost info to chunk if enabled
      enhanced_chunk = if builder.cost_opts.real_time_updates do
        Map.merge(chunk, %{
          cost_data: %{
            current_cost: calculate_chunk_cost(updated_state),
            session_cost: if updated_state.session do
              updated_state.session.total_cost
            else
              nil
            end
          }
        })
      else
        chunk
      end

      user_callback.(enhanced_chunk)
    end
  end

  # Helper functions

  defp get_effective_provider(builder) do
    case builder.request.provider do
      nil -> {:error, :no_provider_specified}
      provider -> {:ok, provider}
    end
  end

  defp get_effective_model(builder, provider) do
    case builder.request.model do
      nil ->
        # Try to get default model for provider
        case ModelConfig.cheapest_model(provider) do
          {model, _pricing} -> {:ok, model}
          nil -> {:error, :no_model_available}
        end
      model -> {:ok, model}
    end
  end

  defp check_cost_limits(builder, provider, model) do
    case builder.cost_opts.limit do
      nil -> :ok
      limit ->
        case estimate_cost(%{builder | request: %{builder.request | provider: provider, model: model}}) do
          {:ok, %{estimated_cost: cost}} when cost <= limit -> :ok
          {:ok, %{estimated_cost: cost}} -> {:error, {:cost_limit_exceeded, cost, limit}}
          {:error, _} -> :ok  # Proceed if can't estimate
        end
    end
  end

  defp check_cache(builder, provider, model) do
    cache_key = generate_cache_key(builder, provider, model)

    case builder.cache_opts.storage_backend do
      :redis ->
        # Use Redis cache
        case Lang.Redis.get(cache_key) do
          {:ok, cached_data} when cached_data != nil ->
            {:hit, Jason.decode!(cached_data)}
          _ -> :miss
        end

      :s3 ->
        # Use S3 storage service
        case Storage.get(cache_key) do
          {:ok, cached_data} -> {:hit, Jason.decode!(cached_data)}
          _ -> :miss
        end

      _ -> :miss
    end
  end

  defp cache_response(builder, provider, model, response, cost_data) do
    cache_key = generate_cache_key(builder, provider, model)
    cache_data = %{
      response: response,
      cost: cost_data,
      cached_at: DateTime.utc_now()
    }

    encoded_data = Jason.encode!(cache_data)

    case builder.cache_opts.storage_backend do
      :redis ->
        ttl = if builder.cache_opts.ttl == :infinity, do: nil, else: builder.cache_opts.ttl
        Lang.Redis.setex(cache_key, ttl, encoded_data)

      :s3 ->
        Storage.put(cache_key, encoded_data, ttl: builder.cache_opts.ttl)

      _ -> :ok
    end
  end

  defp generate_cache_key(builder, provider, model) do
    case builder.cache_opts.key_strategy do
      :content_hash ->
        content = Jason.encode!(%{
          messages: builder.request.messages,
          provider: provider,
          model: model,
          options: builder.request.options
        })

        hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
        "lang:chat:#{hash}"

      :simple ->
        "lang:chat:#{provider}:#{model}:#{System.os_time()}"
    end
  end

  defp calculate_response_cost(response, provider, model) do
    # Extract token usage from response
    token_usage = extract_token_usage(response)

    case Cost.calculate(provider, model, token_usage) do
      {:ok, cost_data} -> cost_data
      {:error, _} -> nil
    end
  end

  defp extract_token_usage(response) do
    # Extract token usage from provider response format
    usage = Map.get(response, :usage, %{})

    %{
      input_tokens: Map.get(usage, :input_tokens, Map.get(usage, :prompt_tokens, 0)),
      output_tokens: Map.get(usage, :output_tokens, Map.get(usage, :completion_tokens, 0))
    }
  end

  defp estimate_request_tokens(messages) do
    # Simple token estimation for messages
    Enum.reduce(messages, 0, fn message, acc ->
      content = Map.get(message, :content, "")
      tokens = Cost.estimate_tokens(content)
      acc + tokens
    end)
  end

  defp update_streaming_cost(cost_state, chunk, builder) do
    # Update token counts based on streaming chunk
    # This is a simplified implementation - real implementation would track deltas
    current_tokens = cost_state.current_tokens

    updated_tokens = case chunk do
      %{usage: usage} ->
        %{
          input_tokens: Map.get(usage, :input_tokens, current_tokens.input_tokens),
          output_tokens: Map.get(usage, :output_tokens, current_tokens.output_tokens)
        }
      _ ->
        # Estimate output tokens from content length
        content_tokens = Cost.estimate_tokens(Map.get(chunk, :content, ""))
        %{
          input_tokens: current_tokens.input_tokens,
          output_tokens: current_tokens.output_tokens + content_tokens
        }
    end

    %{cost_state | current_tokens: updated_tokens}
  end

  defp calculate_chunk_cost(cost_state) do
    # Calculate current cost based on token state
    # This would need provider/model info in real implementation
    token_count = cost_state.current_tokens.input_tokens + cost_state.current_tokens.output_tokens
    # Rough estimate - $0.002 per 1K tokens
    token_count * 0.000002
  end

  defp generate_builder_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp generate_session_id do
    "lsp_session_#{System.os_time(:millisecond)}_#{generate_builder_id()}"
  end
end
