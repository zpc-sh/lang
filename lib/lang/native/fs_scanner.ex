defmodule Lang.Native.FSScanner do
  @moduledoc """
  High-performance filesystem scanner using native Rust implementation.

  This module provides blazing-fast filesystem operations using Rust NIFs:
  - Parallel directory scanning with ripgrep-level performance
  - Content search with regex matching and context
  - Semantic code search using tree-sitter
  - Memory-mapped file access for zero-copy operations

  Integrates seamlessly with the existing LANG architecture and Oban job processing.

  Defaults and behaviors:
  - Scans and searches automatically ignore noisy/system folders like `.git`, `node_modules`, `_build`, `deps`, `target`, etc.
  - Code search supports a configurable `:max_depth` to bound traversal.
  - Scanning supports include/exclude globs and a maximum file size filter.
  """

  use Rustler,
    otp_app: :lang,
    crate: "fs_scanner"

  # Structs are defined in the Rust NIF and will be available at runtime

  # These will be replaced by the NIF functions
  def scan_directory(_path, _max_depth, _include_hidden), do: :erlang.nif_error(:nif_not_loaded)
  def scan_directory_filtered(_path, _max_depth, _include_hidden, _include_globs, _exclude_globs, _max_file_size_bytes),
    do: :erlang.nif_error(:nif_not_loaded)

  def search_content(_root_path, _pattern, _max_results, _context_lines, _case_sensitive),
    do: :erlang.nif_error(:nif_not_loaded)

  def search_code_patterns(_root_path, _language, _pattern, _max_results, _max_depth),
    do: :erlang.nif_error(:nif_not_loaded)

  def get_file_preview(_path, _max_lines), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Scan a directory tree with high-performance parallel processing.

  ## Options
  - `:max_depth` - Maximum directory depth to scan (default: 10)
  - `:include_hidden` - Include hidden files/directories (default: false)
  - `:stats` - Return scanning statistics (default: true)
  - `:include_globs` - List of include globs relative to `path` (e.g., ["**/*.exs"]). If provided, only matching files are included.
  - `:exclude_globs` - List of exclude globs (e.g., ["**/node_modules/**"]). Always excluded.
  - `:max_file_size_bytes` - Skip files larger than this size in bytes (default: no limit)
  - `:include_globs` - List of include globs relative to `path` (e.g., ["**/*.exs"]) – if present, only matches are scanned
  - `:exclude_globs` - List of exclude globs (e.g., ["**/node_modules/**"]) – always excluded
  - `:max_file_size_bytes` - Skip files larger than this size in bytes (default: no limit)

  ## Examples
      iex> Lang.Native.FSScanner.scan("/path/to/project")
      {:ok, %{tree: %FileNode{...}, stats: %ScanStats{...}}}

      iex> Lang.Native.FSScanner.scan("/path/to/project", max_depth: 5, include_hidden: true)
      {:ok, %{tree: %FileNode{...}, stats: %ScanStats{...}}}
  """
  def scan(path, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 10)
    include_hidden = Keyword.get(opts, :include_hidden, false)
    include_stats = Keyword.get(opts, :stats, true)
    timeout = Keyword.get(opts, :timeout, 60_000)
    include_globs = Keyword.get(opts, :include_globs, [])
    exclude_globs = Keyword.get(opts, :exclude_globs, [])
    max_file_size_bytes = Keyword.get(opts, :max_file_size_bytes, 0)

    task =
      Task.async(fn ->
        if (include_globs != [] or exclude_globs != [] or max_file_size_bytes != 0) do
          scan_directory_filtered(
            to_string(path),
            max_depth,
            include_hidden,
            Enum.map(include_globs, &to_string/1),
            Enum.map(exclude_globs, &to_string/1),
            max_file_size_bytes
          )
        else
          scan_directory(to_string(path), max_depth, include_hidden)
        end
      end)

    try do
      case Task.await(task, timeout) do
        {tree, stats} when include_stats ->
          {:ok, %{tree: tree, stats: stats}}

        {tree, _stats} ->
          {:ok, %{tree: tree}}

        {:error, reason} ->
          {:error, reason}
      end
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  @doc """
  Search file contents using ripgrep-powered regex matching.

  ## Options
  - `:max_results` - Maximum number of results to return (default: 100)
  - `:context_lines` - Number of context lines before/after matches (default: 2)
  - `:case_sensitive` - Case-sensitive matching (default: false)
  - `:timeout` - Search timeout in milliseconds (default: 30_000)
  - Always ignores common noisy folders like `.git`, `node_modules`, `_build`, `deps`, and similar

  ## Examples
      iex> Lang.Native.FSScanner.search("/path/to/project", "TODO|FIXME")
      {:ok, [%SearchResult{...}, ...]}

      iex> Lang.Native.FSScanner.search("/path/to/project", "function.*async",
      ...>   max_results: 50, context_lines: 5, case_sensitive: true)
      {:ok, [%SearchResult{...}, ...]}
  """
  def search(path, query, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 100)
    context_lines = Keyword.get(opts, :context_lines, 2)
    case_sensitive = Keyword.get(opts, :case_sensitive, false)
    timeout = Keyword.get(opts, :timeout, 30_000)

    task =
      Task.async(fn ->
        search_content(
          to_string(path),
          to_string(query),
          max_results,
          context_lines,
          case_sensitive
        )
      end)

    try do
      case Task.await(task, timeout) do
        results when is_list(results) ->
          {:ok, results}

        {:error, reason} ->
          {:error, reason}
      end
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  @doc """
  Search code using semantic tree-sitter queries.

  Supports powerful semantic searches using tree-sitter query syntax:
  - Function definitions: `(function_definition name: (identifier) @function)`
  - Method calls: `(call_expression function: (identifier) @method)`
  - Variable assignments: `(assignment_expression left: (identifier) @var)`

  ## Supported Languages
  - rust, javascript, typescript, python, go, java, c, cpp, json

  ## Examples
      iex> Lang.Native.FSScanner.search_code("/path/to/rust/project", "rust",
      ...>   "(function_item name: (identifier) @function)")
      {:ok, [%CodeMatch{...}, ...]}

      iex> Lang.Native.FSScanner.search_code("/path/to/js/project", "javascript",
      ...>   "(call_expression function: (identifier) @fn (#eq? @fn \"console\"))")
      {:ok, [%CodeMatch{...}, ...]}
  """
  def search_code(path, language, pattern, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 100)
    max_depth = Keyword.get(opts, :max_depth, 15)
    timeout = Keyword.get(opts, :timeout, 45_000)

    task =
      Task.async(fn ->
        search_code_patterns(
          to_string(path),
          to_string(language),
          to_string(pattern),
          max_results,
          max_depth
        )
      end)

    try do
      case Task.await(task, timeout) do
        results when is_list(results) ->
          {:ok, results}

        {:error, reason} ->
          {:error, reason}
      end
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  @doc """
  Get a quick preview of file contents.

  ## Examples
      iex> Lang.Native.FSScanner.preview("/path/to/file.ex", max_lines: 20)
      {:ok, ["defmodule MyModule do", "  @moduledoc \"...\"", ...]}
  """
  def preview(path, opts \\ []) do
    max_lines = Keyword.get(opts, :max_lines, 50)

    case get_file_preview(to_string(path), max_lines) do
      lines when is_list(lines) ->
        {:ok, lines}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Async scan for use with Oban jobs and large codebases.

  Returns immediately with a job reference that can be monitored.
  Perfect for integration with LANG's orchestration system.
  """
  def scan_async(path, opts \\ []) do
    _task_opts = [
      # 5 minutes default
      timeout: Keyword.get(opts, :timeout, 300_000),
      on_timeout: :kill_task
    ]

    task =
      Task.async(fn ->
        case scan(path, opts) do
          {:ok, result} ->
            # Optionally send to PubSub for real-time updates
            if pid = Keyword.get(opts, :notify_pid) do
              send(pid, {:scan_complete, path, result})
            end

            # Optionally broadcast via Phoenix PubSub
            if topic = Keyword.get(opts, :pubsub_topic) do
              Phoenix.PubSub.broadcast(Lang.PubSub, topic, {:scan_complete, path, result})
            end

            {:ok, result}

          error ->
            error
        end
      end)

    {:ok, task}
  end

  @doc """
  Search with live updates for real-time UI feedback.

  Streams results as they're found, perfect for LiveView interfaces.
  """
  def search_stream(path, query, opts \\ []) do
    caller = self()
    stream_id = :erlang.unique_integer([:positive])

    spawn_link(fn ->
      # Break large searches into chunks for streaming
      chunk_size = Keyword.get(opts, :chunk_size, 25)
      max_results = Keyword.get(opts, :max_results, 1000)

      # Search in chunks
      Enum.reduce_while(0..div(max_results, chunk_size), [], fn chunk, acc ->
        _start_idx = chunk * chunk_size
        chunk_opts = Keyword.put(opts, :max_results, chunk_size)

        case search(path, query, chunk_opts) do
          {:ok, [_ | _] = results} ->
            send(caller, {:search_chunk, stream_id, results, false})
            {:cont, acc ++ results}

          {:ok, []} ->
            send(caller, {:search_complete, stream_id, acc})
            {:halt, acc}

          {:error, reason} ->
            send(caller, {:search_error, stream_id, reason})
            {:halt, acc}
        end
      end)
    end)

    {:ok, stream_id}
  end

  @doc """
  Integration helpers for LANG's existing architecture.
  """

  def to_analysis_session(scan_result, project_id) do
    %{
      project_id: project_id,
      scan_stats: scan_result.stats,
      file_tree: flatten_tree(scan_result.tree),
      created_at: DateTime.utc_now()
    }
  end

  def to_oban_job(path, opts \\ []) do
    %{
      "path" => to_string(path),
      "opts" => opts,
      "requested_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    |> Lang.Workers.FileSystemScanWorker.new()
  end

  @doc """
  Query helpers for common patterns.
  """

  def common_queries do
    %{
      # Find TODO/FIXME comments
      todos: "TODO|FIXME|HACK|BUG|XXX",

      # Find function definitions (language-agnostic regex)
      functions: "def\\s+\\w+|function\\s+\\w+|fn\\s+\\w+|\\w+\\s*\\(",

      # Find imports/requires
      imports: "import\\s+|require\\s*\\(|use\\s+|#include",

      # Find configuration
      config: "config\\s*[\\[\\(]|settings\\s*=|ENV\\[|process\\.env",

      # Security-related patterns
      security: "password|secret|token|api.?key|private.?key|auth"
    }
  end

  def tree_sitter_queries do
    %{
      rust: %{
        functions: "(function_item name: (identifier) @function)",
        structs: "(struct_item name: (type_identifier) @struct)",
        impls: "(impl_item type: (type_identifier) @impl_type)",
        macros: "(macro_invocation macro: (identifier) @macro)",
        use_statements: "(use_declaration argument: (scoped_identifier) @use)"
      },
      javascript: %{
        functions: "(function_declaration name: (identifier) @function)",
        arrow_functions: "(arrow_function) @arrow_fn",
        classes: "(class_declaration name: (identifier) @class)",
        imports: "(import_statement source: (string) @import_path)",
        exports: "(export_statement) @export"
      },
      typescript: %{
        interfaces: "(interface_declaration name: (type_identifier) @interface)",
        types: "(type_alias_declaration name: (type_identifier) @type)",
        functions: "(function_declaration name: (identifier) @function)",
        classes: "(class_declaration name: (identifier) @class)"
      },
      python: %{
        functions: "(function_definition name: (identifier) @function)",
        classes: "(class_definition name: (identifier) @class)",
        imports: "(import_statement name: (dotted_name) @import)",
        decorators: "(decorator) @decorator"
      }
    }
  end

  # Private helpers

  defp flatten_tree(%{children: nil} = node), do: [Map.drop(node, [:children])]

  defp flatten_tree(%{children: children} = node) when is_list(children) do
    node_without_children = Map.drop(node, [:children])
    [node_without_children | Enum.flat_map(children, &flatten_tree/1)]
  end

  defp flatten_tree(node), do: [node]
end
