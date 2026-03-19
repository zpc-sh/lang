defmodule Lang.LSP.StreamingProtocol do
  @moduledoc """
  Handles streaming of large LSP responses using Phoenix PubSub for internal coordination.

  This module provides efficient streaming for:
  - Large diagnostic results
  - Extensive completion lists
  - Large document symbols
  - Workspace-wide search results
  """

  require Logger
  alias Phoenix.PubSub

  @pubsub Lang.PubSub
  # 64KB chunks
  @chunk_size 64 * 1024

  @type stream_id :: String.t()
  @type stream_options :: [
          chunk_size: pos_integer(),
          timeout: pos_integer()
        ]

  @doc """
  Starts a streaming response for large LSP results.
  Returns a stream ID that clients can use to receive chunks.
  """
  @spec start_stream(map(), Keyword.t()) :: {:ok, stream_id} | {:error, term()}
  def start_stream(response, opts \\ []) do
    stream_id = generate_stream_id()
    chunk_size = Keyword.get(opts, :chunk_size, @chunk_size)

    # Convert response to JSON to check size
    case Jason.encode(response) do
      {:ok, json} when byte_size(json) > chunk_size ->
        # Large response - stream it
        Task.start_link(fn ->
          stream_large_response(stream_id, response, json, opts)
        end)

        {:ok, stream_id}

      {:ok, _json} ->
        # Small response - no need to stream
        {:error, :response_too_small}

      {:error, reason} ->
        {:error, {:encoding_failed, reason}}
    end
  end

  @doc """
  Subscribe to receive chunks for a specific stream.
  """
  @spec subscribe_to_stream(stream_id) :: :ok | {:error, term()}
  def subscribe_to_stream(stream_id) do
    PubSub.subscribe(@pubsub, "lsp_stream:#{stream_id}")
  end

  @doc """
  Unsubscribe from a stream.
  """
  @spec unsubscribe_from_stream(stream_id) :: :ok
  def unsubscribe_from_stream(stream_id) do
    PubSub.unsubscribe(@pubsub, "lsp_stream:#{stream_id}")
  end

  @doc """
  Stream workspace symbols with pagination support.
  """
  @spec stream_workspace_symbols(String.t(), Keyword.t()) :: {:ok, stream_id}
  def stream_workspace_symbols(query, _opts \\ []) do
    stream_id = generate_stream_id()

    Task.start_link(fn ->
      # Simulate searching through workspace
      symbols = search_workspace_symbols(query)

      # Stream results in batches
      symbols
      |> Enum.chunk_every(100)
      |> Enum.with_index()
      |> Enum.each(fn {chunk, index} ->
        is_last = index == div(length(symbols) - 1, 100)

        broadcast_chunk(stream_id, %{
          symbols: chunk,
          total: length(symbols),
          offset: index * 100,
          is_last: is_last
        })

        # Small delay to prevent overwhelming clients
        Process.sleep(10)
      end)
    end)

    {:ok, stream_id}
  end

  @doc """
  Stream diagnostics for large files or workspaces.
  """
  @spec stream_diagnostics(String.t(), String.t(), Keyword.t()) :: {:ok, stream_id}
  def stream_diagnostics(uri, content, opts \\ []) do
    stream_id = generate_stream_id()

    Task.start_link(fn ->
      # Analyze content in chunks for very large files
      lines = String.split(content, "\n")
      chunk_size = Keyword.get(opts, :lines_per_chunk, 1000)

      lines
      |> Enum.chunk_every(chunk_size)
      |> Enum.with_index()
      |> Enum.each(fn {line_chunk, chunk_index} ->
        # Analyze this chunk
        chunk_content = Enum.join(line_chunk, "\n")
        format = extract_format_from_uri(uri)

        case Lang.TextIntelligence.AnalysisEngine.analyze_content(chunk_content, format) do
          {:ok, analysis} ->
            # Adjust line numbers based on chunk offset
            adjusted_diagnostics =
              analysis.diagnostics
              |> adjust_diagnostic_lines(chunk_index * chunk_size)

            broadcast_chunk(stream_id, %{
              uri: uri,
              diagnostics: adjusted_diagnostics,
              chunk_index: chunk_index,
              total_chunks: div(length(lines) - 1, chunk_size) + 1
            })

          {:error, _reason} ->
            # Skip this chunk
            :ok
        end

        Process.sleep(5)
      end)

      # Send completion signal
      broadcast_complete(stream_id)
    end)

    {:ok, stream_id}
  end

  # Private functions

  defp stream_large_response(stream_id, response, json, opts) do
    chunk_size = Keyword.get(opts, :chunk_size, @chunk_size)
    _total_size = byte_size(json)

    # For structured responses, try to split intelligently
    case response do
      %{"result" => %{"items" => items}} when is_list(items) ->
        # Completion response - stream items
        stream_items(stream_id, items, chunk_size)

      %{"result" => %{"symbols" => symbols}} when is_list(symbols) ->
        # Document symbols - stream symbols
        stream_items(stream_id, symbols, chunk_size)

      _ ->
        # Fall back to byte-based streaming
        stream_bytes(stream_id, json, chunk_size)
    end
  end

  defp stream_items(stream_id, items, items_per_chunk) do
    items
    |> Enum.chunk_every(items_per_chunk)
    |> Enum.with_index()
    |> Enum.each(fn {chunk, index} ->
      broadcast_chunk(stream_id, %{
        type: :items,
        items: chunk,
        chunk_index: index,
        total_items: length(items),
        is_last: (index + 1) * items_per_chunk >= length(items)
      })

      Process.sleep(5)
    end)

    broadcast_complete(stream_id)
  end

  defp stream_bytes(stream_id, data, chunk_size) do
    total_chunks = div(byte_size(data) - 1, chunk_size) + 1

    data
    |> :binary.bin_to_list()
    |> Enum.chunk_every(chunk_size)
    |> Enum.with_index()
    |> Enum.each(fn {chunk_bytes, index} ->
      chunk_binary = :binary.list_to_bin(chunk_bytes)

      broadcast_chunk(stream_id, %{
        type: :bytes,
        data: Base.encode64(chunk_binary),
        chunk_index: index,
        total_chunks: total_chunks,
        is_last: index == total_chunks - 1
      })

      Process.sleep(5)
    end)

    broadcast_complete(stream_id)
  end

  defp broadcast_chunk(stream_id, chunk_data) do
    PubSub.broadcast(@pubsub, "lsp_stream:#{stream_id}", {:stream_chunk, stream_id, chunk_data})
  end

  defp broadcast_complete(stream_id) do
    PubSub.broadcast(@pubsub, "lsp_stream:#{stream_id}", {:stream_complete, stream_id})
  end

  defp generate_stream_id do
    "stream_#{:erlang.unique_integer([:positive, :monotonic])}_#{System.system_time(:microsecond)}"
  end

  defp search_workspace_symbols(query) do
    # This would integrate with the actual workspace search
    # For now, return empty list
    []
  end

  defp extract_format_from_uri(uri) do
    case Path.extname(uri) do
      ".md" -> "markdown"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      ".py" -> "python"
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      _ -> "text"
    end
  end

  defp adjust_diagnostic_lines(diagnostics, line_offset) do
    Enum.map(diagnostics, fn diagnostic ->
      %{
        diagnostic
        | range: %{
            diagnostic.range
            | "start" => %{
                diagnostic.range["start"]
                | "line" => diagnostic.range["start"]["line"] + line_offset
              },
              "end" => %{
                diagnostic.range["end"]
                | "line" => diagnostic.range["end"]["line"] + line_offset
              }
          }
      }
    end)
  end
end
