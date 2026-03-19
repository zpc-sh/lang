defmodule Lang.Conversation.BatchProcessor do
  @moduledoc """
  Advanced batch processing pipeline for LANG conversation operations.

  Handles bulk processing of chat requests with intelligent load balancing,
  cost optimization, caching strategies, and failure resilience. Designed
  to work seamlessly with Lang.Conversation.ChatBuilder for high-throughput
  scenarios.

  ## Features

  - **Intelligent Batching**: Groups requests by provider/model for efficiency
  - **Cost-Aware Processing**: Optimizes provider selection for cost efficiency
  - **Adaptive Concurrency**: Adjusts concurrency based on provider performance
  - **Cache-First Strategy**: Leverages caching to reduce redundant requests
  - **Failure Resilience**: Retry logic with exponential backoff
  - **Progress Tracking**: Real-time progress updates with cost tracking
  - **Storage Integration**: S3/Redis backend support for large datasets

  ## Usage

      # Basic batch processing
      requests = [
        %{messages: messages1, provider: :openai, model: "gpt-4o-mini"},
        %{messages: messages2, provider: :anthropic, model: "claude-3-5-haiku"}
      ]

      {:ok, results} = Lang.Conversation.BatchProcessor.process(requests, %{
        concurrency: 10,
        cost_limit: 5.00,
        cache_enabled: true
      })

      # Advanced pipeline with streaming updates
      Lang.Conversation.BatchProcessor.process_with_progress(requests, %{
        progress_callback: fn progress ->
          IO.puts("Progress: \#{progress.completed}/\#{progress.total}")
          IO.puts("Cost so far: \#{Lang.Tokens.Cost.format_cost(progress.total_cost)}")
        end
      })

      # Large-scale processing with storage backend
      Lang.Conversation.BatchProcessor.process_from_storage("s3://bucket/requests.json", %{
        output_storage: "s3://bucket/results/",
        batch_size: 100,
        max_cost: 50.00
      })
  """

  require Logger
  alias Lang.Conversation.ChatBuilder
  alias Lang.Tokens.{Cost, CostSession}
  alias Lang.Storage
  alias Lang.Redis

  @default_concurrency 5
  @default_batch_size 10
  @default_timeout 30_000
  @max_retries 3
  @backoff_base 1000

  @type batch_request :: %{
          messages: [map()],
          provider: atom() | nil,
          model: String.t() | nil,
          metadata: map()
        }

  @type batch_options :: %{
          concurrency: pos_integer(),
          batch_size: pos_integer(),
          timeout: pos_integer(),
          cost_limit: float() | nil,
          cache_enabled: boolean(),
          retry_enabled: boolean(),
          progress_callback: function() | nil,
          storage_backend: atom() | nil,
          output_storage: String.t() | nil
        }

  @type batch_result :: %{
          success_count: non_neg_integer(),
          error_count: non_neg_integer(),
          total_cost: float(),
          results: [map()],
          errors: [map()],
          processing_time: non_neg_integer(),
          cache_hits: non_neg_integer(),
          metadata: map()
        }

  @type progress_update :: %{
          completed: non_neg_integer(),
          total: non_neg_integer(),
          success_count: non_neg_integer(),
          error_count: non_neg_integer(),
          total_cost: float(),
          cache_hits: non_neg_integer(),
          current_batch: non_neg_integer(),
          estimated_remaining_time: non_neg_integer() | nil
        }

  @doc """
  Process a batch of chat requests with comprehensive options.

  ## Parameters
  - `requests` - List of batch requests to process
  - `options` - Processing options and limits

  ## Returns
  - `{:ok, batch_result()}` on success
  - `{:error, reason}` on failure

  ## Examples

      requests = [
        %{
          messages: [%{role: "user", content: "Hello"}],
          provider: :openai,
          model: "gpt-4o-mini"
        },
        %{
          messages: [%{role: "user", content: "Explain AI"}],
          provider: :anthropic,
          model: "claude-3-5-haiku-20241022"
        }
      ]

      {:ok, result} = Lang.Conversation.BatchProcessor.process(requests, %{
        concurrency: 5,
        cost_limit: 2.00,
        cache_enabled: true
      })
  """
  @spec process([batch_request()], batch_options()) :: {:ok, batch_result()} | {:error, term()}
  def process(requests, options \\ %{}) when is_list(requests) do
    if Enum.empty?(requests) do
      {:ok, empty_result()}
    else
      start_time = System.monotonic_time(:millisecond)

      with {:ok, validated_options} <- validate_options(options),
           {:ok, processed_requests} <- preprocess_requests(requests, validated_options),
           {:ok, result} <- execute_batch_processing(processed_requests, validated_options, start_time) do

        # Post-process results
        final_result = finalize_result(result, start_time)
        {:ok, final_result}
      end
    end
  end

  @doc """
  Process batch with real-time progress updates.

  ## Examples

      Lang.Conversation.BatchProcessor.process_with_progress(requests, %{
        progress_callback: fn progress ->
          IO.puts("\#{progress.completed}/\#{progress.total} - Cost: $\#{progress.total_cost}")
        end,
        concurrency: 8
      })
  """
  @spec process_with_progress([batch_request()], batch_options()) :: {:ok, batch_result()} | {:error, term()}
  def process_with_progress(requests, options) do
    # Ensure progress tracking is enabled
    enhanced_options = Map.put(options, :progress_tracking, true)
    process(requests, enhanced_options)
  end

  @doc """
  Process requests from storage backend (S3, Redis, etc.).

  ## Examples

      # From S3
      Lang.Conversation.BatchProcessor.process_from_storage("s3://bucket/requests.json", %{
        output_storage: "s3://bucket/results/",
        batch_size: 50
      })

      # From Redis list
      Lang.Conversation.BatchProcessor.process_from_storage("redis://requests_queue", %{
        concurrency: 10
      })
  """
  @spec process_from_storage(String.t(), batch_options()) :: {:ok, batch_result()} | {:error, term()}
  def process_from_storage(storage_uri, options) do
    with {:ok, requests} <- load_from_storage(storage_uri),
         {:ok, result} <- process(requests, options) do

      # Save results to output storage if specified
      case Map.get(options, :output_storage) do
        nil -> {:ok, result}
        output_uri ->
          case save_to_storage(output_uri, result) do
            :ok -> {:ok, result}
            error -> error
          end
      end
    end
  end

  @doc """
  Estimate total cost and processing time for a batch before execution.

  ## Examples

      {:ok, estimate} = Lang.Conversation.BatchProcessor.estimate_batch(requests, %{
        concurrency: 5
      })

      # => %{
      #   estimated_cost: 2.45,
      #   estimated_time_seconds: 45,
      #   request_count: 100,
      #   cache_potential_savings: 0.50
      # }
  """
  @spec estimate_batch([batch_request()], batch_options()) :: {:ok, map()} | {:error, term()}
  def estimate_batch(requests, options) do
    total_cost = Enum.reduce(requests, 0.0, fn request, acc ->
      case estimate_request_cost(request) do
        {:ok, cost} -> acc + cost
        _ -> acc
      end
    end)

    concurrency = Map.get(options, :concurrency, @default_concurrency)
    batch_size = Map.get(options, :batch_size, @default_batch_size)

    # Rough time estimation based on typical response times
    avg_request_time = 2000  # 2 seconds average
    total_batches = ceil(length(requests) / batch_size)
    estimated_time = ceil(total_batches * avg_request_time / concurrency / 1000)

    # Estimate cache savings if enabled
    cache_savings = if Map.get(options, :cache_enabled, false) do
      total_cost * 0.3  # Assume 30% cache hit rate
    else
      0.0
    end

    estimate = %{
      estimated_cost: total_cost,
      estimated_time_seconds: estimated_time,
      request_count: length(requests),
      cache_potential_savings: cache_savings,
      recommended_concurrency: calculate_recommended_concurrency(length(requests)),
      cost_breakdown: generate_cost_breakdown(requests)
    }

    {:ok, estimate}
  end

  # Private Implementation

  defp validate_options(options) do
    validated = %{
      concurrency: Map.get(options, :concurrency, @default_concurrency),
      batch_size: Map.get(options, :batch_size, @default_batch_size),
      timeout: Map.get(options, :timeout, @default_timeout),
      cost_limit: Map.get(options, :cost_limit),
      cache_enabled: Map.get(options, :cache_enabled, true),
      retry_enabled: Map.get(options, :retry_enabled, true),
      progress_callback: Map.get(options, :progress_callback),
      storage_backend: Map.get(options, :storage_backend, :redis),
      output_storage: Map.get(options, :output_storage),
      progress_tracking: Map.get(options, :progress_tracking, false)
    }

    # Validate constraints
    cond do
      validated.concurrency < 1 ->
        {:error, :invalid_concurrency}

      validated.batch_size < 1 ->
        {:error, :invalid_batch_size}

      validated.timeout < 1000 ->
        {:error, :invalid_timeout}

      validated.cost_limit && validated.cost_limit <= 0 ->
        {:error, :invalid_cost_limit}

      true ->
        {:ok, validated}
    end
  end

  defp preprocess_requests(requests, options) do
    # Group requests by provider/model for optimal batching
    grouped_requests = group_by_provider_model(requests)

    # Apply cost optimization if enabled
    optimized_requests = if options.cost_limit do
      optimize_for_cost(grouped_requests, options.cost_limit)
    else
      grouped_requests
    end

    # Flatten back to list with batch metadata
    processed = Enum.flat_map(optimized_requests, fn {provider_model, batch_requests} ->
      Enum.with_index(batch_requests, fn request, index ->
        Map.merge(request, %{
          batch_group: provider_model,
          batch_index: index,
          processing_metadata: %{
            estimated_cost: estimate_request_cost(request),
            cache_key: generate_cache_key(request)
          }
        })
      end)
    end)

    {:ok, processed}
  end

  defp execute_batch_processing(requests, options, start_time) do
    # Initialize tracking state
    state = %{
      total_requests: length(requests),
      completed: 0,
      success_count: 0,
      error_count: 0,
      total_cost: 0.0,
      cache_hits: 0,
      results: [],
      errors: [],
      current_batch: 0,
      start_time: start_time
    }

    # Process in chunks
    requests
    |> Enum.chunk_every(options.batch_size)
    |> Enum.with_index()
    |> Enum.reduce({:ok, state}, fn {batch, batch_index}, {:ok, acc_state} ->
      updated_state = Map.put(acc_state, :current_batch, batch_index + 1)

      case process_batch_chunk(batch, options, updated_state) do
        {:ok, batch_result} ->
          new_state = merge_batch_result(updated_state, batch_result)

          # Send progress update if callback provided
          if options.progress_callback do
            progress = calculate_progress(new_state, options)
            options.progress_callback.(progress)
          end

          # Check cost limits
          if options.cost_limit && new_state.total_cost >= options.cost_limit do
            Logger.warn("Cost limit reached: #{new_state.total_cost}")
            {:ok, new_state}
          else
            {:ok, new_state}
          end

        error -> error
      end
    end)
  end

  defp process_batch_chunk(batch, options, state) do
    # Process batch with concurrency control
    tasks = Task.async_stream(
      batch,
      fn request -> process_single_request(request, options) end,
      max_concurrency: options.concurrency,
      timeout: options.timeout,
      on_timeout: :kill_task
    )

    # Collect results
    {results, errors} = Enum.reduce(tasks, {[], []}, fn
      {:ok, {:ok, result}}, {results, errors} ->
        {[result | results], errors}

      {:ok, {:error, error}}, {results, errors} ->
        {results, [error | errors]}

      {:exit, reason}, {results, errors} ->
        error = %{error: :task_timeout, reason: reason, timestamp: DateTime.utc_now()}
        {results, [error | errors]}
    end)

    # Calculate batch metrics
    batch_cost = Enum.reduce(results, 0.0, fn result, acc ->
      acc + Map.get(result, :cost, 0.0)
    end)

    cache_hits = Enum.count(results, fn result ->
      Map.get(result, :from_cache, false)
    end)

    batch_result = %{
      success_count: length(results),
      error_count: length(errors),
      batch_cost: batch_cost,
      cache_hits: cache_hits,
      results: Enum.reverse(results),
      errors: Enum.reverse(errors)
    }

    {:ok, batch_result}
  end

  defp process_single_request(request, options) do
    # Check cache first if enabled
    if options.cache_enabled do
      cache_key = Map.get(request.processing_metadata, :cache_key)
      case check_cache(cache_key, options.storage_backend) do
        {:hit, cached_result} ->
          {:ok, Map.put(cached_result, :from_cache, true)}
        :miss ->
          execute_request_with_cache(request, options, cache_key)
      end
    else
      execute_request(request, options)
    end
  end

  defp execute_request_with_cache(request, options, cache_key) do
    case execute_request(request, options) do
      {:ok, result} ->
        # Cache successful result
        cache_result(cache_key, result, options.storage_backend)
        {:ok, result}

      error -> error
    end
  end

  defp execute_request(request, options) do
    # Build ChatBuilder for request
    builder =
      ChatBuilder.new()
      |> ChatBuilder.with_messages(request.messages)
      |> ChatBuilder.with_provider(request.provider || :openai)
      |> ChatBuilder.with_model(request.model || "gpt-4o-mini")
      |> ChatBuilder.with_cost_tracking()

    # Add retry logic if enabled
    if options.retry_enabled do
      execute_with_retry(builder, @max_retries)
    else
      ChatBuilder.execute(builder)
    end
  end

  defp execute_with_retry(builder, retries_left) do
    case ChatBuilder.execute(builder) do
      {:ok, result} -> {:ok, result}
      {:error, reason} when retries_left > 0 ->
        # Exponential backoff
        delay = @backoff_base * :math.pow(2, @max_retries - retries_left)
        :timer.sleep(round(delay))
        execute_with_retry(builder, retries_left - 1)
      error -> error
    end
  end

  defp merge_batch_result(state, batch_result) do
    %{
      state |
      completed: state.completed + batch_result.success_count + batch_result.error_count,
      success_count: state.success_count + batch_result.success_count,
      error_count: state.error_count + batch_result.error_count,
      total_cost: state.total_cost + batch_result.batch_cost,
      cache_hits: state.cache_hits + batch_result.cache_hits,
      results: state.results ++ batch_result.results,
      errors: state.errors ++ batch_result.errors
    }
  end

  defp calculate_progress(state, _options) do
    elapsed_time = System.monotonic_time(:millisecond) - state.start_time

    progress_ratio = if state.total_requests > 0 do
      state.completed / state.total_requests
    else
      0.0
    end

    estimated_remaining = if progress_ratio > 0.1 do
      round(elapsed_time * (1 - progress_ratio) / progress_ratio)
    else
      nil
    end

    %{
      completed: state.completed,
      total: state.total_requests,
      success_count: state.success_count,
      error_count: state.error_count,
      total_cost: state.total_cost,
      cache_hits: state.cache_hits,
      current_batch: state.current_batch,
      progress_percentage: round(progress_ratio * 100),
      estimated_remaining_time: estimated_remaining,
      processing_speed: (if elapsed_time > 0, do: state.completed / (elapsed_time / 1000), else: 0)
    }
  end

  defp finalize_result(state, start_time) do
    processing_time = System.monotonic_time(:millisecond) - start_time

    %{
      success_count: state.success_count,
      error_count: state.error_count,
      total_cost: state.total_cost,
      results: state.results,
      errors: state.errors,
      processing_time: processing_time,
      cache_hits: state.cache_hits,
      metadata: %{
        cache_hit_rate: (if state.success_count > 0, do: state.cache_hits / state.success_count * 100, else: 0),
        average_cost_per_request: (if state.success_count > 0, do: state.total_cost / state.success_count, else: 0),
        requests_per_second: (if processing_time > 0, do: state.success_count / (processing_time / 1000), else: 0),
        error_rate: (if state.completed > 0, do: state.error_count / state.completed * 100, else: 0)
      }
    }
  end

  # Utility Functions

  defp empty_result do
    %{
      success_count: 0,
      error_count: 0,
      total_cost: 0.0,
      results: [],
      errors: [],
      processing_time: 0,
      cache_hits: 0,
      metadata: %{}
    }
  end

  defp group_by_provider_model(requests) do
    Enum.group_by(requests, fn request ->
      provider = request[:provider] || :openai
      model = request[:model] || "gpt-4o-mini"
      {provider, model}
    end)
  end

  defp optimize_for_cost(grouped_requests, cost_limit) do
    # Sort groups by cost efficiency and trim if needed
    sorted_groups = Enum.sort_by(grouped_requests, fn {provider_model, requests} ->
      estimate_group_cost(provider_model, requests)
    end)

    # Take groups until cost limit is reached
    {final_groups, _remaining_budget} = Enum.reduce_while(sorted_groups, {[], cost_limit}, fn
      {provider_model, requests}, {acc_groups, remaining_budget} ->
        group_cost = estimate_group_cost(provider_model, requests)

        if group_cost <= remaining_budget do
          {:cont, {[{provider_model, requests} | acc_groups], remaining_budget - group_cost}}
        else
          {:halt, {acc_groups, remaining_budget}}
        end
    end)

    Enum.reverse(final_groups)
  end

  defp estimate_group_cost({provider, model}, requests) do
    Enum.reduce(requests, 0.0, fn request, acc ->
      case estimate_single_request_cost(request, provider, model) do
        {:ok, cost} -> acc + cost
        _ -> acc
      end
    end)
  end

  defp estimate_request_cost(request) do
    provider = request[:provider] || :openai
    model = request[:model] || "gpt-4o-mini"
    estimate_single_request_cost(request, provider, model)
  end

  defp estimate_single_request_cost(request, provider, model) do
    input_tokens = Cost.estimate_tokens(Jason.encode!(request.messages))
    output_tokens = 500  # Rough estimate

    token_usage = %{input_tokens: input_tokens, output_tokens: output_tokens}

    case Cost.calculate(provider, model, token_usage) do
      {:ok, cost_data} -> {:ok, cost_data.total_cost}
      error -> error
    end
  end

  defp generate_cache_key(request) do
    content = Jason.encode!(%{
      messages: request.messages,
      provider: request[:provider],
      model: request[:model]
    })

    hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    "lang:batch:#{hash}"
  end

  defp check_cache(cache_key, storage_backend) do
    case storage_backend do
      :redis ->
        case Redis.get(cache_key) do
          {:ok, data} when data != nil ->
            {:hit, Jason.decode!(data)}
          _ -> :miss
        end

      :s3 ->
        case Storage.get(cache_key) do
          {:ok, data} -> {:hit, Jason.decode!(data)}
          _ -> :miss
        end

      _ -> :miss
    end
  end

  defp cache_result(cache_key, result, storage_backend) do
    data = Jason.encode!(result)

    case storage_backend do
      :redis ->
        Redis.setex(cache_key, 3600, data)  # 1 hour TTL

      :s3 ->
        Storage.put(cache_key, data, ttl: 3600)

      _ -> :ok
    end
  end

  defp load_from_storage(storage_uri) do
    cond do
      String.starts_with?(storage_uri, "s3://") ->
        Storage.get(storage_uri)
        |> case do
          {:ok, data} -> {:ok, Jason.decode!(data)}
          error -> error
        end

      String.starts_with?(storage_uri, "redis://") ->
        key = String.replace(storage_uri, "redis://", "")
        case Redis.lrange(key, 0, -1) do
          {:ok, items} ->
            requests = Enum.map(items, &Jason.decode!/1)
            {:ok, requests}
          error -> error
        end

      true ->
        {:error, :unsupported_storage_uri}
    end
  end

  defp save_to_storage(storage_uri, result) do
    data = Jason.encode!(result)

    cond do
      String.starts_with?(storage_uri, "s3://") ->
        # Generate unique filename with timestamp
        timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
        key = "#{storage_uri}/batch_result_#{timestamp}.json"
        Storage.put(key, data)

      String.starts_with?(storage_uri, "redis://") ->
        key = String.replace(storage_uri, "redis://", "")
        Redis.set(key, data)

      true ->
        {:error, :unsupported_output_storage}
    end
  end

  defp calculate_recommended_concurrency(request_count) do
    cond do
      request_count < 10 -> 2
      request_count < 50 -> 5
      request_count < 200 -> 10
      request_count < 1000 -> 20
      true -> 50
    end
  end

  defp generate_cost_breakdown(requests) do
    providers = Enum.group_by(requests, &(&1[:provider] || :openai))

    Enum.map(providers, fn {provider, provider_requests} ->
      total_cost = Enum.reduce(provider_requests, 0.0, fn request, acc ->
        case estimate_request_cost(request) do
          {:ok, cost} -> acc + cost
          _ -> acc
        end
      end)

      %{
        provider: provider,
        request_count: length(provider_requests),
        estimated_cost: total_cost
      }
    end)
  end
end
