defmodule Lang.Workers.FileSystemScanWorker do
  @moduledoc """
  Oban worker for high-performance filesystem scanning using native Rust NIFs.

  Integrates with LANG's orchestration system to provide async, distributed
  filesystem analysis with real-time progress updates and result persistence.
  """

  use Oban.Worker,
    queue: :analysis,
    max_attempts: 3,
    tags: ["filesystem", "analysis", "native"]

  alias Lang.Native.FSScanner
  alias Lang.Analysis
  alias Lang.Events
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    %{
      "path" => path,
      "opts" => opts,
      "session_id" => session_id,
      "project_id" => project_id,
      "user_id" => user_id
    } = args

    Logger.info("Starting filesystem scan for path: #{path}")

    try do
      # Broadcast scan start
      broadcast_progress(session_id, :started, %{
        path: path,
        started_at: DateTime.utc_now()
      })

      # Perform the native scan
      scan_opts = [
        max_depth: get_opt(opts, "max_depth", 15),
        include_hidden: get_opt(opts, "include_hidden", false),
        stats: true,
        pubsub_topic: "analysis:#{session_id}",
        timeout: get_opt(opts, "timeout", 300_000)
      ]

      case FSScanner.scan(path, scan_opts) do
        {:ok, %{tree: tree, stats: stats}} ->
          # Convert tree -> analyzed files for session
          case Analysis.create_scan_result(%{session_id: session_id, tree: tree}) do
            {:ok, %{files: created_files}} ->
              # Enqueue per-file analysis
              Enum.each(created_files, fn file ->
                %{"file_id" => file.id}
                |> Lang.Workers.FileAnalyzeWorker.new(queue: :analysis)
                |> Oban.insert()
              end)

              # Broadcast completion
              broadcast_progress(session_id, :completed, %{
                stats: stats,
                files_found: stats.total_files,
                directories_found: stats.total_directories,
                total_size: stats.total_size,
                scan_duration: stats.scan_duration_ms
              })

              # Schedule a run finalize check (will reschedule itself until files are done)
              finalize_delay =
                Application.get_env(:lang, :analysis, [])
                |> Keyword.get(:finalize_delay_seconds, 120)

              Lang.Workers.RunFinalizeWorker
              |> apply(:new, [
                %{"run_id" => session_id},
                [queue: :analysis, scheduled_at: DateTime.add(DateTime.utc_now(), finalize_delay)]
              ])
              |> Oban.insert()

              # Track event for analytics
              Events.track_event(%{
                event_type: "filesystem_scan_completed",
                user_id: user_id,
                metadata: %{
                  session_id: session_id,
                  project_id: project_id,
                  files_scanned: stats.total_files,
                  scan_duration_ms: stats.scan_duration_ms,
                  path: path
                }
              })

              Logger.info(
                "Filesystem scan completed successfully for #{path}: #{stats.total_files} files, #{stats.total_directories} directories"
              )

              {:ok, %{files_count: length(created_files), stats: stats}}

            {:error, reason} ->
              Logger.error("Failed to create analyzed files from scan: #{inspect(reason)}")
              broadcast_error(session_id, "Failed to ingest scan results", reason)
              {:error, reason}
          end

        {:error, :timeout} ->
          Logger.warning("Filesystem scan timed out for path: #{path}")

          broadcast_error(
            session_id,
            "Scan timed out",
            "The filesystem scan took too long to complete"
          )

          {:error, :timeout}

        {:error, reason} ->
          Logger.error("Filesystem scan failed for #{path}: #{inspect(reason)}")
          broadcast_error(session_id, "Scan failed", reason)
          {:error, reason}
      end
    rescue
      exception ->
        Logger.error(
          "Exception during filesystem scan: #{Exception.format(:error, exception, __STACKTRACE__)}"
        )

        broadcast_error(session_id, "Scan exception", Exception.message(exception))
        {:error, exception}
    end
  end

  @doc """
  Queue a filesystem scan job with the specified options.
  """
  def scan_async(path, session_id, project_id, user_id, opts \\ []) do
    %{
      "path" => to_string(path),
      "session_id" => session_id,
      "project_id" => project_id,
      "user_id" => user_id,
      "opts" => stringify_opts(opts),
      "requested_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    |> new(
      queue: :analysis,
      priority: get_priority(opts),
      scheduled_at: get_scheduled_at(opts),
      tags: ["filesystem", "scan", "project:#{project_id}"]
    )
    |> Oban.insert()
  end

  @doc """
  Queue multiple analysis jobs based on scan results.
  """
  def scan_and_analyze(path, session_id, project_id, user_id, opts \\ []) do
    analysis_types = Keyword.get(opts, :analysis_types, [:content_search, :semantic_analysis])

    scan_opts = Keyword.put(opts, :queue_analysis, analysis_types)
    scan_async(path, session_id, project_id, user_id, scan_opts)
  end

  # Private functions

  # Per-file analysis now enqueued directly after ingest; keep helpers below for future batch jobs if needed

  defp queue_content_search_job(scan_result, opts) do
    search_patterns = get_opt(opts, "search_patterns", default_search_patterns())

    %{
      "scan_result_id" => scan_result.id,
      "session_id" => scan_result.session_id,
      "patterns" => search_patterns
    }
    |> Lang.Workers.ContentSearchWorker.new(queue: :analysis)
    |> Oban.insert()
  end

  defp queue_semantic_analysis_job(scan_result, opts) do
    languages = extract_languages_from_stats(scan_result.stats)

    Enum.each(languages, fn language ->
      %{
        "scan_result_id" => scan_result.id,
        "session_id" => scan_result.session_id,
        "language" => language,
        "analysis_depth" => get_opt(opts, "semantic_depth", "standard")
      }
      |> Lang.Workers.SemanticAnalysisWorker.new(queue: :analysis)
      |> Oban.insert()
    end)
  end

  defp queue_security_scan_job(scan_result, opts) do
    %{
      "scan_result_id" => scan_result.id,
      "session_id" => scan_result.session_id,
      "security_level" => get_opt(opts, "security_level", "standard")
    }
    |> Lang.Workers.SecurityScanWorker.new(queue: :analysis)
    |> Oban.insert()
  end

  defp queue_dependency_analysis_job(scan_result, opts) do
    %{
      "scan_result_id" => scan_result.id,
      "session_id" => scan_result.session_id,
      "analyze_versions" => get_opt(opts, "analyze_versions", true)
    }
    |> Lang.Workers.DependencyAnalysisWorker.new(queue: :analysis)
    |> Oban.insert()
  end

  defp broadcast_progress(session_id, status, data) do
    Phoenix.PubSub.broadcast(Lang.PubSub, "analysis:#{session_id}", {
      :scan_progress,
      status,
      data
    })
  end

  defp broadcast_error(session_id, message, details) do
    Phoenix.PubSub.broadcast(Lang.PubSub, "analysis:#{session_id}", {
      :scan_error,
      %{
        message: message,
        details: details,
        timestamp: DateTime.utc_now()
      }
    })
  end

  defp get_opt(opts, key, default) do
    case Map.get(opts, key) do
      nil -> default
      value -> value
    end
  end

  defp stringify_opts(opts) do
    opts
    |> Enum.into(%{})
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.into(%{})
  end

  defp get_priority(opts) do
    case Keyword.get(opts, :priority) do
      :high -> 1
      :normal -> 2
      :low -> 3
      priority when is_integer(priority) -> priority
      _ -> 2
    end
  end

  defp get_scheduled_at(opts) do
    case Keyword.get(opts, :scheduled_at) do
      nil ->
        nil

      %DateTime{} = dt ->
        dt

      seconds when is_integer(seconds) ->
        DateTime.utc_now() |> DateTime.add(seconds, :second)

      _ ->
        nil
    end
  end

  defp default_search_patterns do
    [
      "TODO|FIXME|HACK|BUG|XXX",
      "password|secret|token|api.?key",
      "console\\.log|print\\(|println!",
      "import\\s+|require\\s*\\(|use\\s+",
      "function\\s+|def\\s+|fn\\s+|class\\s+"
    ]
  end

  defp extract_languages_from_stats(%{files_by_extension: extensions}) do
    extensions
    |> Map.keys()
    |> Enum.map(&extension_to_language/1)
    |> Enum.filter(& &1)
    |> Enum.uniq()
  end

  defp extract_languages_from_stats(_), do: []

  defp extension_to_language(ext) do
    case String.downcase(ext) do
      "rs" -> "rust"
      "ex" -> "elixir"
      "exs" -> "elixir"
      "js" -> "javascript"
      "jsx" -> "javascript"
      "ts" -> "typescript"
      "tsx" -> "typescript"
      "py" -> "python"
      "go" -> "go"
      "java" -> "java"
      "c" -> "c"
      "cpp" -> "cpp"
      "h" -> "c"
      "hpp" -> "cpp"
      "rb" -> "ruby"
      "php" -> "php"
      "cs" -> "csharp"
      "swift" -> "swift"
      _ -> nil
    end
  end

  # Job cancellation support
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 30s, 2m, 8m
    trunc(:math.pow(2, attempt) * 15)
  end

  @impl Oban.Worker
  def timeout(_job) do
    # 10 minutes max per scan job
    :timer.minutes(10)
  end
end
