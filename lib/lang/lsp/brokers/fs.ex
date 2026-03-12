defmodule Lang.LSP.Brokers.FS do
  @moduledoc """
  In-process filesystem domain broker.

  Uses native Rust NIFs via `Lang.Native.FSScanner` for all operations.
  Enforces an optional workspace root boundary when available in configuration.
  """

  @behaviour Lang.LSP.DomainBroker
  alias Lang.LSP.Configuration

  @impl true
  def init(_config), do: {:ok, :ready}

  @impl true
  def handle(%{"method" => method, "params" => params} = _req, %Configuration{} = cfg) do
    case method do
      "lang.fs.scan" -> do_scan(params, cfg)
      "lang.fs.search" -> do_search(params, cfg)
      "lang.fs.search_code" -> do_search_code(params, cfg)
      "lang.fs.preview" -> do_preview(params, cfg)
      _ -> {:error, -32601, "Method not found"}
    end
  end

  @impl true
  def terminate(_state), do: :ok

  # ---------------------------------------------------------------------------
  # Operations
  # ---------------------------------------------------------------------------
  defp do_scan(params, cfg) do
    path = coalesce(params, ["path", "root"]) |> to_string()
    with :ok <- within_root(path, cfg.workspace_root) do
      max_depth = int(params["max_depth"], 10)
      case Lang.Native.FSScanner.scan(path, max_depth: max_depth) do
        {:ok, res} -> {:ok, res}
        {:error, reason} -> {:error, -32002, inspect(reason)}
      end
    end
  end

  defp do_search(params, cfg) do
    path = coalesce(params, ["path", "root"]) |> to_string()
    query = to_string(params["query"] || params["pattern"] || "")
    with :ok <- within_root(path, cfg.workspace_root) do
      max_results = int(params["max_results"], 100)
      case Lang.Native.FSScanner.search(path, query, max_results: max_results) do
        {:ok, results} -> {:ok, results}
        {:error, reason} -> {:error, -32002, inspect(reason)}
      end
    end
  end

  defp do_search_code(params, cfg) do
    path = coalesce(params, ["path", "root"]) |> to_string()
    language = to_string(params["language"] || "")
    pattern = to_string(params["pattern"] || "")
    with :ok <- within_root(path, cfg.workspace_root) do
      max_results = int(params["max_results"], 100)
      max_depth = int(params["max_depth"], 15)
      case Lang.Native.FSScanner.search_code(path, language, pattern, max_results: max_results, max_depth: max_depth) do
        {:ok, matches} -> {:ok, matches}
        {:error, reason} -> {:error, -32002, inspect(reason)}
      end
    end
  end

  defp do_preview(params, cfg) do
    path = to_string(params["path"] || "")
    with :ok <- within_root(path, cfg.workspace_root) do
      max_lines = int(params["max_lines"], 200)
      case Lang.Native.FSScanner.preview(path, max_lines: max_lines) do
        {:ok, lines} when is_list(lines) -> {:ok, Enum.join(lines, "\n")}
        {:ok, bin} when is_binary(bin) -> {:ok, bin}
        {:error, reason} -> {:error, -32002, inspect(reason)}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  defp within_root(_path, nil), do: :ok
  defp within_root(path, root) when is_binary(path) and is_binary(root) do
    ex_path = Path.expand(path)
    ex_root = Path.expand(root)
    if String.starts_with?(ex_path, ex_root) do
      :ok
    else
      {:error, -32602, "path_outside_workspace_root", %{path: ex_path, root: ex_root}}
    end
  end

  defp int(nil, default), do: default
  defp int(v, _default) when is_integer(v), do: v
  defp int(v, default) do
    case Integer.parse(to_string(v)) do
      {n, _} -> n
      :error -> default
    end
  end

  defp coalesce(map, keys) do
    Enum.find_value(keys, fn k ->
      case map[k] do
        nil -> nil
        v -> v
      end
    end)
  end
end

