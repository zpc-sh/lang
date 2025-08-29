defmodule Nullity.CDFM.Adapters.FileAdapter.FSScanner do
  @moduledoc """
  FileAdapter implementation backed by Lang.Native.FSScanner (NIFs).
  """
  @behaviour Nullity.CDFM.Adapters.FileAdapter

  alias Lang.Native.FSScanner

  @impl true
  def read(path) do
    case FSScanner.preview(path, max_lines: 100_000) do
      {:ok, lines} when is_list(lines) -> {:ok, Enum.join(lines, "\n")}
      {:ok, bin} when is_binary(bin) -> {:ok, bin}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def write(path, content) do
    cond do
      function_exported?(FSScanner, :write_file, 2) ->
        case FSScanner.write_file(path, content) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      true ->
        try do
          # Ensure the directory exists then write with Elixir fallback
          dir = Path.dirname(path)
          File.mkdir_p!(dir)

          case File.write(path, content) do
            :ok -> :ok
            {:error, reason} -> {:error, reason}
          end
        rescue
          e -> {:error, e}
        end
    end
  end

  @impl true
  def exists?(path) do
    cond do
      function_exported?(FSScanner, :exists?, 1) -> FSScanner.exists?(path) == true
      true -> File.exists?(path)
    end
  end

  @impl true
  def mtime(path) do
    cond do
      function_exported?(FSScanner, :stat, 1) ->
        case FSScanner.stat(path) do
          {:ok, %{mtime: mtime}} -> {:ok, mtime}
          {:error, reason} -> {:error, reason}
        end

      true ->
        case File.stat(path) do
          {:ok, %File.Stat{mtime: mtime}} -> {:ok, mtime}
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
