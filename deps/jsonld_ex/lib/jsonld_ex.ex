defmodule JsonldEx do
  @moduledoc """
  High-performance JSON-LD processing library for Elixir with Rust NIF backend.
  """

  alias JsonldEx.Native

  def expand(document, opts \\ []) do
    document
    |> prepare_input()
    |> Native.expand(opts)
    |> decode_result()
  end

  def expand_turbo(document, opts \\ []) do
    # Use zero-copy binary expansion for maximum performance
    case Jason.encode(document) do
      {:ok, json_binary} ->
        json_binary
        |> Native.expand_binary(opts)
        |> decode_binary_result()
      error -> error
    end
  end

  # Batch processing using BEAM's strength - concurrent processing
  def expand_batch(documents, opts \\ []) do
    documents
    |> Task.async_stream(&expand_turbo(&1, opts), max_concurrency: System.schedulers_online())
    |> Stream.map(fn {:ok, result} -> result end)
    |> Enum.to_list()
  end

  # Rust-side parallel batch processing with SIMD optimizations
  def expand_batch_rust(documents, _opts \\ []) do
    # Convert documents to JSON strings for zero-copy processing
    document_strings = Enum.map(documents, fn doc ->
      case Jason.encode(doc) do
        {:ok, json_string} -> json_string
        _ -> "{\"error\": \"Invalid document\"}"
      end
    end)
    
    case Native.batch_expand(document_strings) do
      {:ok, results} ->
        Enum.map(results, fn result_str ->
          case Jason.decode(result_str) do
            {:ok, decoded} -> {:ok, decoded}
            error -> error
          end
        end)
      error -> error
    end
  end

  # Pipeline processing for LANG - process documents as they arrive
  def expand_stream(document_stream, opts \\ []) do
    document_stream
    |> Stream.map(&expand_turbo(&1, opts))
  end

  def compact(document, context, opts \\ []) do
    with input <- prepare_input(document),
         ctx <- prepare_input(context) do
      input
      |> Native.compact(ctx, opts)
      |> decode_result()
    end
  end

  defp prepare_input(input) when is_binary(input), do: input
  defp prepare_input(input), do: Jason.encode!(input)

  defp decode_result({:ok, result}) when is_binary(result) do
    case Jason.decode(result) do
      {:ok, decoded} -> {:ok, decoded}
      error -> error
    end
  end
  
  defp decode_result(result), do: result

  defp decode_binary_result({:ok, result_binary}) when is_binary(result_binary) do
    case Jason.decode(result_binary) do
      {:ok, decoded} -> {:ok, decoded}
      error -> error
    end
  end
  
  defp decode_binary_result(result), do: result
end
