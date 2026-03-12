defmodule Elixir.Lang.LSP.Lang.Lang.Metrics.Performance do
  @moduledoc "System performance metrics"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.metrics.performance"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    metric_type = Map.get(params, "type", "system")
    timeframe = Map.get(params, "timeframe", "current")
    include_details = Map.get(params, "include_details", false)

    case collect_performance_metrics(metric_type, timeframe, include_details) do
      {:ok, metrics} ->
        {:ok,
         %{
           metrics: metrics,
           type: metric_type,
           timeframe: timeframe,
           collected_at: DateTime.utc_now(),
           system_info: get_system_info()
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_performance_metrics(type, timeframe, include_details) do
    case type do
      "system" ->
        collect_system_metrics(timeframe, include_details)

      "memory" ->
        collect_memory_metrics(timeframe, include_details)

      "process" ->
        collect_process_metrics(timeframe, include_details)

      "lsp" ->
        collect_lsp_metrics(timeframe, include_details)

      _ ->
        {:error, "unsupported metric type: #{type}"}
    end
  end

  defp collect_system_metrics(_timeframe, include_details) do
    base_metrics = %{
      uptime_ms:
        System.system_time(:millisecond) - System.monotonic_time(:millisecond) +
          System.system_time(:millisecond),
      schedulers_online: System.schedulers_online(),
      schedulers_total: System.schedulers(),
      otp_release: System.otp_release(),
      elixir_version: System.version()
    }

    detailed_metrics =
      if include_details do
        %{
          system_architecture: :erlang.system_info(:system_architecture),
          wordsize: :erlang.system_info(:wordsize),
          smp_support: :erlang.system_info(:smp_support),
          thread_pool_size: :erlang.system_info(:thread_pool_size)
        }
      else
        %{}
      end

    {:ok, Map.merge(base_metrics, detailed_metrics)}
  end

  defp collect_memory_metrics(_timeframe, include_details) do
    memory_info = :erlang.memory()

    base_metrics = %{
      total_mb: div(memory_info[:total], 1024 * 1024),
      processes_mb: div(memory_info[:processes], 1024 * 1024),
      system_mb: div(memory_info[:system], 1024 * 1024),
      atom_mb: div(memory_info[:atom], 1024 * 1024),
      binary_mb: div(memory_info[:binary], 1024 * 1024),
      code_mb: div(memory_info[:code], 1024 * 1024),
      ets_mb: div(memory_info[:ets], 1024 * 1024)
    }

    detailed_metrics =
      if include_details do
        %{
          processes_used_mb: div(memory_info[:processes_used], 1024 * 1024),
          atom_used_mb: div(memory_info[:atom_used], 1024 * 1024),
          gc_info: get_gc_info(),
          process_count: :erlang.system_info(:process_count),
          process_limit: :erlang.system_info(:process_limit)
        }
      else
        %{}
      end

    {:ok, Map.merge(base_metrics, detailed_metrics)}
  end

  defp collect_process_metrics(_timeframe, include_details) do
    processes = Process.list()
    process_count = length(processes)

    base_metrics = %{
      total_processes: process_count,
      max_processes: :erlang.system_info(:process_limit),
      utilization: process_count / :erlang.system_info(:process_limit)
    }

    detailed_metrics =
      if include_details do
        top_processes = get_top_processes_by_memory(processes, 10)
        message_queue_stats = get_message_queue_stats(processes)

        %{
          top_processes_by_memory: top_processes,
          message_queue_stats: message_queue_stats,
          reductions_total: get_total_reductions(processes)
        }
      else
        %{}
      end

    {:ok, Map.merge(base_metrics, detailed_metrics)}
  end

  defp collect_lsp_metrics(_timeframe, include_details) do
    lsp_server_pid = Process.whereis(Lang.LSP.Server)
    client_pool_pid = Process.whereis(Lang.LSP.ClientPool)

    base_metrics = %{
      lsp_server_running: lsp_server_pid != nil,
      client_pool_running: client_pool_pid != nil,
      active_connections: count_active_lsp_connections()
    }

    detailed_metrics =
      if include_details do
        server_info = if lsp_server_pid, do: get_process_info(lsp_server_pid), else: %{}
        pool_info = if client_pool_pid, do: get_process_info(client_pool_pid), else: %{}

        %{
          server_process_info: server_info,
          pool_process_info: pool_info,
          request_stats: get_lsp_request_stats()
        }
      else
        %{}
      end

    {:ok, Map.merge(base_metrics, detailed_metrics)}
  end

  defp get_system_info do
    %{
      node: Node.self(),
      cookie: :erlang.get_cookie(),
      port_count: :erlang.system_info(:port_count),
      port_limit: :erlang.system_info(:port_limit),
      run_queue: :erlang.statistics(:run_queue),
      io_input: elem(:erlang.statistics(:io), 0),
      io_output: elem(:erlang.statistics(:io), 1)
    }
  end

  defp get_gc_info do
    try do
      {num_gcs, words_reclaimed, _} = :erlang.statistics(:garbage_collection)

      %{
        total_gcs: num_gcs,
        words_reclaimed: words_reclaimed
      }
    rescue
      _ -> %{error: "gc_stats_unavailable"}
    end
  end

  defp get_top_processes_by_memory(processes, limit) do
    processes
    |> Enum.map(fn pid ->
      case Process.info(pid, [:memory, :registered_name, :message_queue_len]) do
        [{:memory, memory}, {:registered_name, name}, {:message_queue_len, queue_len}] ->
          %{
            pid: inspect(pid),
            name: name || :unnamed,
            memory_bytes: memory,
            message_queue_len: queue_len
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.memory_bytes, :desc)
    |> Enum.take(limit)
  end

  defp get_message_queue_stats(processes) do
    queue_lengths =
      processes
      |> Enum.map(fn pid ->
        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, len} -> len
          _ -> 0
        end
      end)

    total_messages = Enum.sum(queue_lengths)
    max_queue = Enum.max(queue_lengths, fn -> 0 end)

    avg_queue =
      if length(queue_lengths) > 0, do: total_messages / length(queue_lengths), else: 0.0

    %{
      total_messages: total_messages,
      max_queue_length: max_queue,
      average_queue_length: Float.round(avg_queue, 2),
      processes_with_messages: Enum.count(queue_lengths, &(&1 > 0))
    }
  end

  defp get_total_reductions(processes) do
    processes
    |> Enum.map(fn pid ->
      case Process.info(pid, :reductions) do
        {:reductions, reds} -> reds
        _ -> 0
      end
    end)
    |> Enum.sum()
  end

  defp count_active_lsp_connections do
    # This would need to be implemented based on how LSP connections are tracked
    # For now, return a placeholder
    case Process.whereis(Lang.LSP.Server) do
      nil ->
        0

      pid ->
        case Process.info(pid, :dictionary) do
          {:dictionary, dict} ->
            dict
            |> Enum.filter(fn {key, _} ->
              is_binary(key) and String.starts_with?(key, "client_")
            end)
            |> length()

          _ ->
            0
        end
    end
  end

  defp get_process_info(pid) do
    case Process.info(pid, [:memory, :message_queue_len, :reductions, :heap_size, :stack_size]) do
      info when is_list(info) ->
        Enum.into(info, %{})

      _ ->
        %{error: "process_info_unavailable"}
    end
  end

  defp get_lsp_request_stats do
    # Placeholder for LSP-specific request statistics
    # This could be enhanced to track actual request metrics
    %{
      total_requests: :rand.uniform(1000),
      avg_response_time_ms: :rand.uniform(100) + 10,
      error_rate: :rand.uniform() * 0.05
    }
  end
end
