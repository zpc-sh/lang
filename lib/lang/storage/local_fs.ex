defmodule Lang.Storage.LocalFS do
  @moduledoc """
  Local filesystem adapter backed by Lang.Native.FSScanner (Rust NIFs).

  All operations are constrained to a provided workspace root. Paths are
  normalized and validated to prevent directory traversal outside the root.
  """

  @behaviour Lang.Storage.Adapter
  alias Lang.Native.FSScanner

  @impl true
  def normalize(root, path) do
    root = Path.expand(root)
    candidate = Path.expand(Path.join(root, path || "."))
    if String.starts_with?(candidate, root) do
      {:ok, candidate}
    else
      {:error, :outside_root}
    end
  end

  @impl true
  def list(root, path, opts \\ []) do
    with {:ok, abs} <- normalize(root, path),
         {:ok, result} <- FSScanner.scan(abs, max_depth: Keyword.get(opts, :depth, 1), include_hidden: Keyword.get(opts, :include_hidden, false), stats: false) do
      entries =
        case result do
          %{tree: %{children: children}} when is_list(children) ->
            Enum.map(children, fn node ->
              %{
                name: node.name,
                uri: path_to_uri(node.path || Path.join(abs, node.name)),
                kind: node.node_type == :Directory && :directory || :file,
                size: node.size,
                mtime: node.modified_time
              }
            end)

          %{tree: _leaf} ->
            []
        end

      {:ok, entries}
    else
      {:error, reason} -> {:error, reason}
      other -> other
    end
  end

  @impl true
  def stat(root, path) do
    with {:ok, abs} <- normalize(root, path) do
      case FSScanner.scan(abs, max_depth: 0, include_hidden: true, stats: false) do
        {:ok, %{tree: node}} ->
          kind =
            case node.node_type do
              :Directory -> :directory
              :File -> :file
              _ -> :file
            end

          {:ok, %{exists: true, kind: kind, size: node.size, mtime: node.modified_time}}

        {:error, _} ->
          {:ok, %{exists: false}}
      end
    end
  end

  @impl true
  def read(root, path, opts \\ []) do
    # For large reads, prefer preview with high max_lines to avoid memory spikes
    max_lines = Keyword.get(opts, :max_lines, 200_000)
    with {:ok, abs} <- normalize(root, path) do
      case FSScanner.preview(abs, max_lines: max_lines) do
        {:ok, lines} -> {:ok, IO.iodata_to_binary(Enum.intersperse(lines, "\n"))}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def preview(root, path, max_lines \\ 200) do
    with {:ok, abs} <- normalize(root, path) do
      FSScanner.preview(abs, max_lines: max_lines)
    end
  end

  @impl true
  def search(root, pattern, opts \\ []) do
    with {:ok, abs} <- normalize(root, ".") do
      FSScanner.search(abs, pattern, opts)
    end
  end

  @impl true
  def search_code(root, language, query, opts \\ []) do
    with {:ok, abs} <- normalize(root, ".") do
      FSScanner.search_code(abs, language, query, opts)
    end
  end

  @impl true
  def scan(root, opts \\ []) do
    with {:ok, abs} <- normalize(root, ".") do
      FSScanner.scan(abs, opts)
    end
  end

  @impl true
  def write(root, path, content, mode \\ :replace) do
    with {:ok, abs} <- normalize(root, path) do
      case mode do
        :replace -> do_write(abs, content, [:write])
        :append -> do_write(abs, content, [:append])
        _ -> {:error, :invalid_mode}
      end
    end
  end

  defp do_write(path, content, modes) do
    # Small targeted exception to NIF-only FS rule: NIFs don’t expose write yet
    # Keep writes bounded and simple; use :file for performance and atomicity
    case :file.open(String.to_charlist(path), modes) do
      {:ok, io} ->
        try do
          :ok = :file.write(io, IO.iodata_to_binary(content))
          :ok
        after
          :file.close(io)
        end
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def move(root, from, to) do
    with {:ok, abs_from} <- normalize(root, from),
         {:ok, abs_to} <- normalize(root, to) do
      case :file.rename(String.to_charlist(abs_from), String.to_charlist(abs_to)) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def delete(root, path, recursive? \\ false) do
    with {:ok, abs} <- normalize(root, path) do
      case recursive? do
        true -> rm_rf(abs)
        false -> if File.dir?(abs), do: File.rmdir(abs), else: File.rm(abs)
      end
    end
  end

  defp rm_rf(path) do
    case File.rm_rf(path) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
    end
  end

  defp path_to_uri(path) do
    "file://" <> Path.expand(path)
  end
end

