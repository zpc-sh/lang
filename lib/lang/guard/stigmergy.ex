defmodule Lang.Guard.Stigmergy do
  @moduledoc """
  Stigmergy heat record store for the Guard Mesh purification engine.

  Stores heat records from scan+wash cycles, enabling multi-pass
  convergence. Each shielded agent that processes a file leaves a
  trail — subsequent agents read the heat map and focus on remaining
  hot zones. Over many passes, the repo converges to clean.

  Storage: ETS table keyed by {file_path, pass_number}
  Persistence: Periodic flush to disk (JSON) for survival across restarts
  Broadcast: Heat map updates pushed to gopher mesh + LSP diagnostics
  """

  use GenServer
  require Logger

  @table :guard_stigmergy
  @aggregate_table :guard_stigmergy_aggregate
  @flush_interval :timer.minutes(5)
  @persistence_path "priv/guard/stigmergy.json"

  defstruct [:started_at, :last_flush, stats: %{records: 0, files_tracked: 0, passes_total: 0}]

  # -- Public API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a scan+wash result for a file. Creates a heat record with
  region-level detail including flip directions and wash results.
  """
  @spec record_scan(String.t(), map(), map()) :: :ok
  def record_scan(file_path, scan_result, agent_info) when is_binary(file_path) do
    GenServer.cast(__MODULE__, {:record_scan, file_path, scan_result, agent_info})
  end

  @doc "Get all heat records for a file, sorted by time (newest first)."
  @spec get_heat(String.t()) :: [map()]
  def get_heat(file_path) when is_binary(file_path) do
    case :ets.match_object(@table, {{file_path, :_}, :_}) do
      records ->
        records
        |> Enum.map(fn {{_path, _pass}, record} -> record end)
        |> Enum.sort_by(& &1.scanned_at, {:desc, DateTime})
    end
  end

  @doc "Get the aggregate heat map: %{file_path => status_summary}."
  @spec get_heatmap() :: map()
  def get_heatmap do
    :ets.tab2list(@aggregate_table)
    |> Enum.into(%{}, fn {path, summary} -> {path, summary} end)
  end

  @doc "Get files that are still hot or partially purified (need more passes)."
  @spec get_hot_files() :: [map()]
  def get_hot_files do
    :ets.tab2list(@aggregate_table)
    |> Enum.filter(fn {_path, summary} -> summary.status in [:hot, :partially_purified] end)
    |> Enum.sort_by(fn {_path, summary} -> summary.risk_score end, :desc)
    |> Enum.map(fn {path, summary} -> Map.put(summary, :file_path, path) end)
  end

  @doc """
  Get the adversarial manifold for a file — the collected flip directions
  across all passes, revealing attack topology.
  """
  @spec get_manifold(String.t()) :: map()
  def get_manifold(file_path) when is_binary(file_path) do
    records = get_heat(file_path)

    regions =
      records
      |> Enum.flat_map(& &1.regions)
      |> Enum.sort_by(fn r -> elem(r.byte_range, 0) end)

    flip_directions =
      regions
      |> Enum.map(fn r -> %{byte_range: r.byte_range, direction: r.flip_direction, risk: r.risk} end)
      |> Enum.uniq_by(& &1.byte_range)

    passes = length(records)

    convergence =
      case records do
        [] -> 0.0
        [latest | _] -> latest.confidence
      end

    %{
      file_path: file_path,
      regions: regions,
      flip_directions: flip_directions,
      passes: passes,
      convergence: convergence,
      topology: compute_topology(flip_directions)
    }
  end

  @doc "Merge a new pass of heat records into the aggregate."
  @spec merge_pass(non_neg_integer(), [map()]) :: :ok
  def merge_pass(pass_number, heat_records) when is_list(heat_records) do
    Enum.each(heat_records, fn record ->
      :ets.insert(@table, {{record.file_path, pass_number}, record})
      update_aggregate(record.file_path)
    end)
  end

  @doc "Get stats about the stigmergy store."
  @spec stats() :: map()
  def stats, do: GenServer.call(__MODULE__, :stats)

  # -- GenServer Callbacks --

  @impl true
  def init(_opts) do
    Logger.info("Guard Stigmergy store started")

    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@aggregate_table, [:named_table, :set, :public, read_concurrency: true])

    # Load persisted records if available
    load_from_disk()

    # Schedule periodic flush
    Process.send_after(self(), :flush_to_disk, @flush_interval)

    {:ok, %__MODULE__{started_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast({:record_scan, file_path, scan_result, agent_info}, state) do
    pass_number = next_pass_number(file_path)

    heat_record = build_heat_record(file_path, scan_result, agent_info, pass_number)

    :ets.insert(@table, {{file_path, pass_number}, heat_record})
    update_aggregate(file_path)

    # Broadcast to telemetry
    try do
      Lang.Guard.Telemetry.threat_detected(%{
        type: :stigmergy_record,
        file_path: file_path,
        risk_score: heat_record.risk_score,
        pass: pass_number
      })
    rescue
      _ -> :ok
    end

    stats = %{
      state.stats
      | records: state.stats.records + 1,
        files_tracked: :ets.info(@aggregate_table, :size),
        passes_total: state.stats.passes_total + 1
    }

    {:noreply, %{state | stats: stats}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_info(:flush_to_disk, state) do
    flush_to_disk()
    Process.send_after(self(), :flush_to_disk, @flush_interval)
    {:noreply, %{state | last_flush: DateTime.utc_now()}}
  end

  # -- Private --

  defp build_heat_record(file_path, scan_result, agent_info, pass_number) do
    regions = build_regions(scan_result)

    overall_status =
      cond do
        scan_result.risk_score < 0.1 -> :clean
        scan_result.risk_score < 0.5 -> :partially_purified
        true -> :hot
      end

    %{
      file_path: file_path,
      scanned_at: DateTime.utc_now(),
      scanned_by: agent_info[:agent_id] || "unknown",
      agent_type: agent_info[:agent_type] || "unknown",
      risk_score: scan_result.risk_score,
      regions: regions,
      overall_status: overall_status,
      confidence: compute_confidence(scan_result, pass_number),
      pass_number: pass_number
    }
  end

  defp build_regions(scan_result) do
    regions = []

    # Build regions from scan flags and flip directions
    regions =
      if scan_result[:injection_hits] && scan_result.injection_hits > 0 do
        [
          %{
            byte_range: {0, 0},
            line_range: {0, 0},
            risk: min(scan_result.injection_hits * 0.3, 1.0),
            flip_direction: Map.get(scan_result, :flip_direction, :injection_pattern),
            flags: ["injection_pattern"],
            action: :neutralized,
            wash_result: "neutralized #{scan_result.injection_hits} injection pattern(s)"
          }
          | regions
        ]
      else
        regions
      end

    regions =
      if scan_result[:bidi_hits] && scan_result.bidi_hits > 0 do
        [
          %{
            byte_range: {0, 0},
            line_range: {0, 0},
            risk: min(scan_result.bidi_hits * 0.15, 1.0),
            flip_direction: Map.get(scan_result, :flip_direction, :bidi_control_signal),
            flags: ["bidi_override_detected"],
            action: :neutralized,
            wash_result: "stripped #{scan_result.bidi_hits} bidi control character(s)"
          }
          | regions
        ]
      else
        regions
      end

    regions =
      if scan_result[:entropy_anomaly] do
        [
          %{
            byte_range: {0, 0},
            line_range: {0, 0},
            risk: 0.2,
            flip_direction: Map.get(scan_result, :flip_direction, :high_entropy_control_signal),
            flags: ["entropy_anomaly"],
            action: :flagged,
            wash_result: "entropy anomaly detected — needs deeper analysis"
          }
          | regions
        ]
      else
        regions
      end

    regions =
      if scan_result[:rop_candidates] && length(scan_result.rop_candidates) > 5 do
        [
          %{
            byte_range: {0, 0},
            line_range: {0, 0},
            risk: min(length(scan_result.rop_candidates) * 0.02, 1.0),
            flip_direction: Map.get(scan_result, :flip_direction, :rop_fragment_cluster),
            flags: ["rop_fragment_cluster"],
            action: :annotated,
            wash_result: "warning: #{length(scan_result.rop_candidates)} potential ROP fragments"
          }
          | regions
        ]
      else
        regions
      end

    regions =
      if scan_result[:coercion_hits] && scan_result.coercion_hits > 0 do
        [
          %{
            byte_range: {0, 0},
            line_range: {0, 0},
            risk: min(scan_result.coercion_hits * 0.25, 1.0),
            flip_direction: Map.get(scan_result, :flip_direction, :coercion_attempt),
            flags: ["coercion_pattern"],
            action: :neutralized,
            wash_result: "neutralized #{scan_result.coercion_hits} coercion pattern(s)"
          }
          | regions
        ]
      else
        regions
      end

    Enum.reverse(regions)
  end

  defp compute_confidence(_scan_result, pass_number) do
    # Confidence increases with each pass (diminishing returns)
    # Pass 1: 0.5, Pass 2: 0.75, Pass 3: 0.875, ...
    1.0 - :math.pow(0.5, pass_number)
  end

  defp next_pass_number(file_path) do
    case :ets.match(@table, {{file_path, :"$1"}, :_}) do
      [] -> 1
      passes -> (passes |> List.flatten() |> Enum.max()) + 1
    end
  end

  defp update_aggregate(file_path) do
    records = get_heat(file_path)

    case records do
      [] ->
        :ok

      _ ->
        latest = hd(records)
        pass_count = length(records)
        agent_types = records |> Enum.map(& &1.agent_type) |> Enum.uniq()

        # Cross-validation: if 2+ different agent types agree it's clean, mark verified
        status =
          cond do
            latest.overall_status == :clean and length(agent_types) >= 2 -> :verified
            true -> latest.overall_status
          end

        summary = %{
          status: status,
          risk_score: latest.risk_score,
          passes: pass_count,
          last_scanned: latest.scanned_at,
          agent_types: agent_types,
          confidence: latest.confidence
        }

        :ets.insert(@aggregate_table, {file_path, summary})
    end
  end

  defp compute_topology(flip_directions) do
    # Group flip directions by type to reveal attack structure
    flip_directions
    |> Enum.group_by(& &1.direction)
    |> Enum.map(fn {direction, regions} ->
      %{
        direction: direction,
        count: length(regions),
        total_risk: regions |> Enum.map(& &1.risk) |> Enum.sum() |> Float.round(3)
      }
    end)
    |> Enum.sort_by(& &1.total_risk, :desc)
  end

  defp flush_to_disk do
    records =
      :ets.tab2list(@table)
      |> Enum.map(fn {{path, pass}, record} ->
        record
        |> Map.put(:_key_path, path)
        |> Map.put(:_key_pass, pass)
        |> Map.update(:scanned_at, nil, fn
          %DateTime{} = dt -> DateTime.to_iso8601(dt)
          other -> other
        end)
      end)

    dir = Path.dirname(@persistence_path)

    case File.mkdir_p(dir) do
      :ok ->
        case Jason.encode(records) do
          {:ok, json} ->
            File.write(@persistence_path, json)

          {:error, reason} ->
            Logger.warning("Stigmergy flush: encode failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("Stigmergy flush: mkdir_p failed: #{inspect(reason)}")
    end
  rescue
    e -> Logger.warning("Stigmergy flush failed: #{inspect(e)}")
  end

  defp load_from_disk do
    case File.read(@persistence_path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, records} when is_list(records) ->
            Enum.each(records, fn record ->
              path = record["_key_path"]
              pass = record["_key_pass"]

              if path && pass do
                clean_record =
                  record
                  |> Map.delete("_key_path")
                  |> Map.delete("_key_pass")
                  |> atomize_keys()

                :ets.insert(@table, {{path, pass}, clean_record})
                update_aggregate(path)
              end
            end)

            Logger.info("Stigmergy: loaded #{length(records)} records from disk")

          _ ->
            :ok
        end

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Logger.warning("Stigmergy: failed to load from disk: #{inspect(reason)}")
    end
  rescue
    _ -> :ok
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) ->
        {String.to_existing_atom(k), atomize_keys(v)}

      {k, v} ->
        {k, atomize_keys(v)}
    end)
  rescue
    # If atom doesn't exist, keep the string key
    _ -> map
  end

  defp atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  defp atomize_keys(other), do: other
end
