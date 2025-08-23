defmodule Lang.MCP.Servers.FilesystemServer do
  @moduledoc """
  Example filesystem MCP server for testing the broker security layer.

  This is a minimal MCP server implementation that demonstrates how MCP servers
  are isolated and managed by the broker. It provides basic filesystem operations
  while being completely sandboxed and controlled by the security layer.

  ## Security Model
  This server runs as an isolated GenServer process under the broker's supervision.
  All requests are validated by the security layer before reaching this server.
  The server cannot make any direct network calls or access files outside its
  configured root directory.

  ## Supported Operations
  - fs/list - List files in a directory
  - fs/read - Read file contents
  - fs/stat - Get file statistics
  - fs/exists - Check if file exists
  """

  use GenServer
  require Logger

  # Server state
  defstruct [
    :root_path,
    :config,
    :stats,
    :created_at,
    :last_request_at
  ]

  @type server_state :: %__MODULE__{
          root_path: String.t(),
          config: map(),
          stats: map(),
          created_at: DateTime.t(),
          last_request_at: DateTime.t()
        }

  ## Public API

  def start_link(config \\ %{}) do
    GenServer.start_link(__MODULE__, config)
  end

  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  ## GenServer Callbacks

  @impl true
  def init(config) do
    Logger.debug("Starting filesystem MCP server", config: config)

    root_path = Map.get(config, "root_path", ".")

    # Validate root path exists and is accessible
    case validate_root_path(root_path) do
      :ok ->
        state = %__MODULE__{
          root_path: Path.expand(root_path),
          config: config,
          stats: %{
            requests_handled: 0,
            errors_encountered: 0,
            files_read: 0,
            directories_listed: 0
          },
          created_at: DateTime.utc_now(),
          last_request_at: nil
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to initialize filesystem server", reason: reason, root_path: root_path)
        {:stop, {:invalid_root_path, reason}}
    end
  end

  @impl true
  def handle_call({:mcp_request, request}, _from, state) do
    Logger.debug("Filesystem server received request", request: request)

    updated_state = %{
      state
      | last_request_at: DateTime.utc_now(),
        stats: %{state.stats | requests_handled: state.stats.requests_handled + 1}
    }

    case handle_mcp_request(request, updated_state) do
      {:ok, response, new_state} ->
        {:reply, {:ok, response}, new_state}

      {:error, reason, new_state} ->
        error_state = %{
          new_state
          | stats: %{new_state.stats | errors_encountered: new_state.stats.errors_encountered + 1}
        }

        {:reply, {:error, reason}, error_state}
    end
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    health_status = %{
      status: :healthy,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.created_at),
      requests_handled: state.stats.requests_handled,
      files_read: state.stats.files_read,
      directories_listed: state.stats.directories_listed,
      root_path_accessible: File.dir?(state.root_path)
    }

    {:reply, {:ok, health_status}, state}
  end

  @impl true
  def handle_cast(:shutdown, state) do
    Logger.info("Filesystem MCP server shutting down gracefully")
    {:stop, :normal, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.debug("Filesystem MCP server terminated", reason: reason)
    :ok
  end

  ## Private Functions

  defp handle_mcp_request(%{"method" => "fs/list"} = request, state) do
    params = Map.get(request, "params", %{})
    path = Map.get(params, "path", ".")

    case list_directory(path, state) do
      {:ok, files} ->
        response = %{
          "result" => %{
            "files" => files,
            "path" => path
          }
        }

        updated_stats = %{state.stats | directories_listed: state.stats.directories_listed + 1}
        {:ok, response, %{state | stats: updated_stats}}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp handle_mcp_request(%{"method" => "fs/read"} = request, state) do
    params = Map.get(request, "params", %{})
    path = Map.get(params, "path")

    if is_nil(path) do
      {:error, "Missing required parameter: path", state}
    else
      case read_file(path, state) do
        {:ok, content} ->
          response = %{
            "result" => %{
              "content" => content,
              "path" => path,
              "encoding" => "utf-8"
            }
          }

          updated_stats = %{state.stats | files_read: state.stats.files_read + 1}
          {:ok, response, %{state | stats: updated_stats}}

        {:error, reason} ->
          {:error, reason, state}
      end
    end
  end

  defp handle_mcp_request(%{"method" => "fs/stat"} = request, state) do
    params = Map.get(request, "params", %{})
    path = Map.get(params, "path")

    if is_nil(path) do
      {:error, "Missing required parameter: path", state}
    else
      case get_file_stats(path, state) do
        {:ok, stats} ->
          response = %{
            "result" => %{
              "stats" => stats,
              "path" => path
            }
          }

          {:ok, response, state}

        {:error, reason} ->
          {:error, reason, state}
      end
    end
  end

  defp handle_mcp_request(%{"method" => "fs/exists"} = request, state) do
    params = Map.get(request, "params", %{})
    path = Map.get(params, "path")

    if is_nil(path) do
      {:error, "Missing required parameter: path", state}
    else
      full_path = build_safe_path(path, state)
      exists = File.exists?(full_path)

      response = %{
        "result" => %{
          "exists" => exists,
          "path" => path
        }
      }

      {:ok, response, state}
    end
  end

  defp handle_mcp_request(%{"method" => method}, state) do
    Logger.warning("Unsupported filesystem method", method: method)
    {:error, "Unsupported method: #{method}", state}
  end

  defp handle_mcp_request(request, state) do
    Logger.warning("Invalid filesystem request format", request: request)
    {:error, "Invalid request format", state}
  end

  defp list_directory(path, state) do
    full_path = build_safe_path(path, state)

    case File.ls(full_path) do
      {:ok, entries} ->
        files = Enum.map(entries, fn entry ->
          entry_path = Path.join(full_path, entry)
          stat = File.stat!(entry_path)

          %{
            "name" => entry,
            "type" => if(stat.type == :directory, do: "directory", else: "file"),
            "size" => stat.size,
            "modified" => DateTime.from_unix!(stat.mtime, :second) |> DateTime.to_iso8601()
          }
        end)

        {:ok, files}

      {:error, reason} ->
        Logger.warning("Failed to list directory", path: full_path, reason: reason)
        {:error, "Failed to list directory: #{reason}"}
    end
  rescue
    error ->
      Logger.error("Error listing directory", path: path, error: inspect(error))
      {:error, "Directory listing failed"}
  end

  defp read_file(path, state) do
    full_path = build_safe_path(path, state)

    # Check file size to prevent reading huge files
    case File.stat(full_path) do
      {:ok, %{size: size}} when size > 1_000_000 ->
        {:error, "File too large (max 1MB)"}

      {:ok, _stat} ->
        case File.read(full_path) do
          {:ok, content} ->
            # Ensure content is valid UTF-8
            case String.valid?(content) do
              true ->
                {:ok, content}
              false ->
                # Return base64 for binary files
                {:ok, Base.encode64(content)}
            end

          {:error, reason} ->
            Logger.warning("Failed to read file", path: full_path, reason: reason)
            {:error, "Failed to read file: #{reason}"}
        end

      {:error, reason} ->
        Logger.warning("Failed to stat file", path: full_path, reason: reason)
        {:error, "File not found or inaccessible"}
    end
  rescue
    error ->
      Logger.error("Error reading file", path: path, error: inspect(error))
      {:error, "File reading failed"}
  end

  defp get_file_stats(path, state) do
    full_path = build_safe_path(path, state)

    case File.stat(full_path) do
      {:ok, stat} ->
        stats = %{
          "type" => Atom.to_string(stat.type),
          "size" => stat.size,
          "mode" => stat.mode,
          "accessed" => DateTime.from_unix!(stat.atime, :second) |> DateTime.to_iso8601(),
          "modified" => DateTime.from_unix!(stat.mtime, :second) |> DateTime.to_iso8601(),
          "created" => DateTime.from_unix!(stat.ctime, :second) |> DateTime.to_iso8601()
        }

        {:ok, stats}

      {:error, reason} ->
        Logger.warning("Failed to stat file", path: full_path, reason: reason)
        {:error, "Failed to get file stats: #{reason}"}
    end
  rescue
    error ->
      Logger.error("Error getting file stats", path: path, error: inspect(error))
      {:error, "File stats failed"}
  end

  defp build_safe_path(relative_path, state) do
    # Remove any path traversal attempts (already done by security layer, but double-check)
    clean_path =
      relative_path
      |> String.replace(~r/\.\.+/, "")  # Remove .. sequences
      |> String.replace(~r/\/+/, "/")   # Normalize slashes
      |> String.trim("/")               # Remove leading/trailing slashes

    # Build full path within root directory
    Path.join(state.root_path, clean_path)
    |> Path.expand()
    |> ensure_within_root(state.root_path)
  end

  defp ensure_within_root(path, root_path) do
    expanded_root = Path.expand(root_path)
    expanded_path = Path.expand(path)

    if String.starts_with?(expanded_path, expanded_root) do
      expanded_path
    else
      # Path escapes root directory, return root instead
      Logger.warning("Path traversal attempt blocked",
        path: path,
        root: root_path,
        expanded_path: expanded_path,
        expanded_root: expanded_root
      )
      expanded_root
    end
  end

  defp validate_root_path(root_path) do
    expanded_path = Path.expand(root_path)

    cond do
      not File.exists?(expanded_path) ->
        {:error, :path_does_not_exist}

      not File.dir?(expanded_path) ->
        {:error, :path_is_not_directory}

      true ->
        :ok
    end
  end
end
