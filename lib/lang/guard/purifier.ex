defmodule Lang.Guard.Purifier do
  @moduledoc """
  Orchestrates the scan→wash→record→write purification cycle.

  A shielded agent uses the purifier to process files: scan with the
  sign-flip active (recording where the flip activates), wash the
  adversarial content, write back a purified version, and emit a
  heat record to the stigmergy store.

  Over multiple passes by different agents, the heat map converges
  and the repo trends toward clean.
  """

  use GenServer
  require Logger

  defstruct [
    :started_at,
    stats: %{files_purified: 0, regions_neutralized: 0, regions_remaining: 0}
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Run a full purification cycle on a single file.

  1. Read file content
  2. Scan with full 5-layer scanner (records flip activations)
  3. Wash to produce purified content
  4. Record heat record in stigmergy store
  5. Return result (caller decides whether to write back)

  Returns `{:ok, purification_result}` with original and purified risk,
  region details, and the heat record emitted.
  """
  @spec purify(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def purify(file_path, agent_info \\ %{}) do
    GenServer.call(__MODULE__, {:purify, file_path, agent_info}, :timer.seconds(30))
  end

  @doc """
  Purify a batch of files, ordered by heat map priority (hottest first).
  """
  @spec purify_batch([String.t()], map(), keyword()) :: [map()]
  def purify_batch(file_paths, agent_info \\ %{}, _opts \\ []) do
    # Sort by existing heat (hottest first, unscanned before partially_purified)
    sorted =
      file_paths
      |> Enum.map(fn path ->
        heatmap = Lang.Guard.Stigmergy.get_heatmap()

        priority =
          case Map.get(heatmap, path) do
            nil -> 1.0
            %{status: :hot, risk_score: r} -> r
            %{status: :partially_purified, risk_score: r} -> r * 0.8
            %{status: :clean} -> 0.1
            %{status: :verified} -> 0.0
          end

        {path, priority}
      end)
      |> Enum.sort_by(fn {_path, priority} -> priority end, :desc)
      |> Enum.map(fn {path, _} -> path end)

    Enum.map(sorted, fn path ->
      case purify(path, agent_info) do
        {:ok, result} -> result
        {:error, reason} -> %{file_path: path, error: reason}
      end
    end)
  end

  @doc """
  Get next files to purify, prioritized by risk and scan status.
  Unscanned files come first, then hot, then partially_purified.
  """
  @spec next_targets(non_neg_integer()) :: [map()]
  def next_targets(count \\ 10) do
    Lang.Guard.Stigmergy.get_hot_files()
    |> Enum.take(count)
  end

  @doc "Get purifier statistics."
  @spec stats() :: map()
  def stats, do: GenServer.call(__MODULE__, :stats)

  # -- GenServer Callbacks --

  @impl true
  def init(_opts) do
    Logger.info("Guard Purifier started")
    {:ok, %__MODULE__{started_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_call({:purify, file_path, agent_info}, _from, state) do
    case do_purify(file_path, agent_info) do
      {:ok, result} ->
        stats = %{
          state.stats
          | files_purified: state.stats.files_purified + 1,
            regions_neutralized:
              state.stats.regions_neutralized + result.regions_neutralized,
            regions_remaining:
              state.stats.regions_remaining + result.regions_remaining
        }

        {:reply, {:ok, result}, %{state | stats: stats}}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  # -- Private --

  defp do_purify(file_path, agent_info) do
    # Step 1: Read file content
    case File.read(file_path) do
      {:ok, content} ->
        do_purify_content(file_path, content, agent_info)

      {:error, reason} ->
        Logger.warning("Purifier: cannot read #{file_path}: #{inspect(reason)}")
        {:error, {:file_read_error, reason}}
    end
  end

  defp do_purify_content(file_path, content, agent_info) do
    # Step 2: Scan with full scanner (records flip activations)
    {:ok, scan_result} = Lang.Guard.Scanner.scan(content)

    original_risk = scan_result.risk_score

    # Step 3: Wash to produce purified content
    {:ok, wash_result} = Lang.Guard.Washer.wash(content)

    purified_content = wash_result.text

    # Step 4: Re-scan purified content to measure improvement
    {:ok, post_scan} = Lang.Guard.Scanner.scan(purified_content)
    purified_risk = post_scan.risk_score

    # Count regions
    regions_neutralized = count_neutralized(scan_result, post_scan)
    regions_remaining = count_remaining(post_scan)

    # Step 5: Record heat record in stigmergy store
    Lang.Guard.Stigmergy.record_scan(file_path, scan_result, agent_info)

    result = %{
      file_path: file_path,
      original_risk: original_risk,
      purified_risk: purified_risk,
      purified_content: purified_content,
      annotations: wash_result.annotations,
      regions_neutralized: regions_neutralized,
      regions_remaining: regions_remaining,
      scan_result: scan_result,
      heat_record: %{
        file_path: file_path,
        original_risk: original_risk,
        purified_risk: purified_risk,
        agent_info: agent_info
      }
    }

    Logger.info(
      "Purified #{file_path}: risk #{original_risk} → #{purified_risk}, " <>
        "#{regions_neutralized} neutralized, #{regions_remaining} remaining"
    )

    {:ok, result}
  rescue
    e ->
      Logger.error("Purifier error on #{file_path}: #{inspect(e)}")
      {:error, {:purify_error, Exception.message(e)}}
  end

  defp count_neutralized(pre_scan, post_scan) do
    pre_flags = MapSet.new(pre_scan.flags)
    post_flags = MapSet.new(post_scan.flags)
    MapSet.difference(pre_flags, post_flags) |> MapSet.size()
  end

  defp count_remaining(post_scan) do
    length(post_scan.flags)
  end
end
