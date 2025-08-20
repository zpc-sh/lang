defmodule Lang.Native.FsWatcher do
  @moduledoc """
  LANG Filesystem Watcher - Cross-Platform File System Monitoring with Architectural Rules

  This module provides Elixir bindings to the ultra-optimized Rust NIF implementation
  for cross-platform filesystem watching with real-time architectural rule checking.

  ## Features
  - Cross-platform filesystem event handling (inotify, kqueue, Windows events)
  - Event coalescing to reduce noise from rapid file changes
  - Real-time architectural rule validation
  - Memory-mapped file processing for large codebases

  ## Platform Support
  - Linux: inotify-based watching with kernel-level optimization
  - macOS: kqueue-based watching with FSEvents integration
  - Windows: ReadDirectoryChangesW with completion ports
  - Cross-platform: Unified API with platform-specific optimizations

  ## Performance Features
  - Event coalescing reduces noise from rapid file changes
  - Lock-free concurrent data structures for high throughput
  - NUMA-aware memory allocation for large directory trees
  - Parallel rule checking with automatic load balancing
  """

  use RustlerPrecompiled,
    otp_app: :lang,
    crate: "fs_watcher",
    base_url: "https://github.com/nocsi/lang/releases/download/v",
    force_build: System.get_env("RUSTLER_PRECOMPILATION_EXAMPLE_BUILD") in ["1", "true"],
    version: "0.1.0"

  # ============================================================================
  # WATCHER LIFECYCLE MANAGEMENT
  # ============================================================================

  @doc """
  Create a new filesystem watcher with specified configuration.
  """
  @spec create_watcher(String.t(), boolean(), [String.t()], boolean()) ::
          {:ok, reference()} | {:error, term()}
  def create_watcher(_id, _recursive, _patterns, _enable_rules),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Destroy a filesystem watcher and clean up all associated resources.
  """
  @spec destroy_watcher(reference()) :: :ok | {:error, term()}
  def destroy_watcher(_watcher), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Add a path to be monitored by the filesystem watcher.
  """
  @spec add_watch_path(reference(), String.t()) :: :ok | {:error, term()}
  def add_watch_path(_watcher, _path), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Remove a path from filesystem monitoring.
  """
  @spec remove_watch_path(reference(), String.t()) :: :ok | {:error, term()}
  def remove_watch_path(_watcher, _path), do: :erlang.nif_error(:nif_not_loaded)

  # ============================================================================
  # ARCHITECTURAL RULE CONFIGURATION
  # ============================================================================

  @doc """
  Configure architectural rules for real-time validation.
  """
  @spec set_architectural_rules(String.t()) :: :ok | {:error, term()}
  def set_architectural_rules(_rules_json), do: :erlang.nif_error(:nif_not_loaded)

  # ============================================================================
  # EVENT RETRIEVAL AND PROCESSING
  # ============================================================================

  @doc """
  Retrieve filesystem events from the watcher.

  Returns up to `max_events` events that have occurred since the last call.
  Events include metadata and any architectural rule violations detected.
  """
  @spec get_events(reference(), non_neg_integer()) :: {:ok, [String.t()]} | {:error, term()}
  def get_events(_watcher, _max_events), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Get comprehensive statistics about watcher performance and activity.
  """
  @spec get_statistics(reference()) :: {:ok, String.t()} | {:error, term()}
  def get_statistics(_watcher), do: :erlang.nif_error(:nif_not_loaded)

  # ============================================================================
  # EVENT PROCESSING UTILITIES
  # ============================================================================

  @doc """
  Manually coalesce a batch of events to reduce noise.
  """
  @spec coalesce_events([String.t()], non_neg_integer()) :: {:ok, [String.t()]} | {:error, term()}
  def coalesce_events(_events_json, _window_ms), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Batch validate architectural rules against a list of file paths.
  """
  @spec batch_validate_rules([String.t()]) :: {:ok, [String.t()]} | {:error, term()}
  def batch_validate_rules(_file_paths), do: :erlang.nif_error(:nif_not_loaded)

  # ============================================================================
  # DIRECTORY SCANNING AND METADATA
  # ============================================================================

  @doc """
  Scan a directory tree and return all file paths up to a maximum depth.
  """
  @spec scan_directory_tree(String.t(), non_neg_integer()) ::
          {:ok, [String.t()]} | {:error, term()}
  def scan_directory_tree(_root_path, _max_depth), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Get file metadata for a batch of file paths in parallel.
  """
  @spec get_file_metadata_batch([String.t()]) :: {:ok, [String.t()]} | {:error, term()}
  def get_file_metadata_batch(_file_paths), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Setup real-time performance monitoring for the watcher.
  """
  @spec setup_real_time_monitoring(reference()) :: :ok | {:error, term()}
  def setup_real_time_monitoring(_watcher), do: :erlang.nif_error(:nif_not_loaded)

  # ============================================================================
  # HIGH-LEVEL CONVENIENCE FUNCTIONS
  # ============================================================================

  @doc """
  Create and configure a watcher with common architectural rules.
  """
  @spec create_elixir_project_watcher(String.t(), keyword()) ::
          {:ok, reference()} | {:error, term()}
  def create_elixir_project_watcher(project_path, opts \\ []) do
    watcher_id = "elixir_project_#{:erlang.phash2(project_path)}"
    patterns = Keyword.get(opts, :patterns, ["**/*.ex", "**/*.exs", "**/mix.exs"])
    enable_rules = Keyword.get(opts, :enable_rules, true)
    recursive = Keyword.get(opts, :recursive, true)
    strict_mode = Keyword.get(opts, :strict_mode, false)

    with {:ok, watcher} <- create_watcher(watcher_id, recursive, patterns, enable_rules),
         :ok <- add_watch_path(watcher, project_path) do
      if enable_rules do
        rules = elixir_architectural_rules(strict_mode)
        rules_json = Jason.encode!(rules)

        case set_architectural_rules(rules_json) do
          :ok -> {:ok, watcher}
          {:error, reason} -> {:error, reason}
        end
      else
        {:ok, watcher}
      end
    end
  end

  @doc """
  Watch a directory with automatic rule violation reporting.
  """
  @spec watch_with_reporting(String.t(), function(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def watch_with_reporting(project_path, callback, opts \\ []) do
    interval_ms = Keyword.get(opts, :interval_ms, 5000)
    patterns = Keyword.get(opts, :patterns, ["**/*.ex", "**/*.exs"])

    case create_elixir_project_watcher(project_path, patterns: patterns) do
      {:ok, watcher} ->
        pid =
          spawn_link(fn ->
            watch_loop(watcher, callback, interval_ms)
          end)

        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Health check for the filesystem watcher native engine.
  """
  @spec health_check() :: {:ok, :healthy} | {:error, term()}
  def health_check() do
    try do
      # Test basic watcher creation and destruction
      test_id = "health_check_#{System.monotonic_time()}"

      with {:ok, watcher} <- create_watcher(test_id, false, ["*.tmp"], false),
           :ok <- destroy_watcher(watcher) do
        {:ok, :healthy}
      end
    catch
      _ -> {:error, :nif_not_loaded}
    end
  end

  # ============================================================================
  # PRIVATE HELPER FUNCTIONS
  # ============================================================================

  defp elixir_architectural_rules(strict_mode) do
    base_rules = [
      %{
        id: "no_direct_database_access",
        name: "No Direct Database Access in Web Layer",
        description: "Web controllers should not directly access the database",
        pattern: "lib/*_web/**/*.ex",
        severity: "error",
        enabled: true
      },
      %{
        id: "require_module_doc",
        name: "Module Documentation Required",
        description: "All modules should have @moduledoc documentation",
        pattern: "lib/**/*.ex",
        severity: "warning",
        enabled: true
      },
      %{
        id: "test_coverage",
        name: "Test Coverage Required",
        description: "All modules should have corresponding tests",
        pattern: "lib/**/*.ex",
        severity: "info",
        enabled: true
      }
    ]

    if strict_mode do
      base_rules ++
        [
          %{
            id: "function_length_strict",
            name: "Strict Function Length Limit",
            description: "Functions should not exceed 20 lines in strict mode",
            pattern: "**/*.ex",
            severity: "error",
            enabled: true
          },
          %{
            id: "require_type_specs",
            name: "Type Specifications Required",
            description: "All public functions must have @spec definitions",
            pattern: "lib/**/*.ex",
            severity: "error",
            enabled: true
          }
        ]
    else
      base_rules
    end
  end

  defp watch_loop(watcher, callback, interval_ms) do
    receive do
      :stop ->
        :ok
    after
      interval_ms ->
        case get_events(watcher, 1000) do
          {:ok, events_json} ->
            events = Enum.map(events_json, &Jason.decode!/1)

            violations =
              events
              |> Enum.flat_map(& &1["rule_violations"])
              |> Enum.reject(&is_nil/1)

            if length(violations) > 0 do
              callback.(violations)
            end

          {:error, _reason} ->
            :ok
        end

        watch_loop(watcher, callback, interval_ms)
    end
  end
end
