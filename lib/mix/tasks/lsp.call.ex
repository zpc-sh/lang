defmodule Mix.Tasks.Lsp.Call do
  use Mix.Task
  @shortdoc "Call an LSP method over TCP: mix lsp.call METHOD [--json '{...}'] [--file path]"

  @moduledoc """
  Calls an LSP JSON-RPC method on the local server (localhost:LSP_PORT) with parameters.

  Examples:

      mix lsp.call lang.fs.scan --json '{"path":"."}'
      mix lsp.call lang.analyze.document --file input.json

  Notes:
  - If using `--file`, the file content is read via `Lang.Native.FSScanner.preview/2` per project guidelines.
  - If both `--json` and `--file` are provided, `--json` takes precedence.
  """

  alias Lang.LSP.API
  alias Lang.Native.FSScanner

  @impl true
  def run(args) do
    Mix.Task.run("loadpaths")

    {opts, rest, _} = OptionParser.parse(args, strict: [json: :string, file: :string])
    method = List.first(rest)

    cond do
      is_nil(method) ->
        Mix.raise("Usage: mix lsp.call METHOD [--json '{...}'] [--file path]")

      true ->
        params =
          cond do
            json = opts[:json] -> decode_json!(json)
            file = opts[:file] -> read_json_file!(file)
            true -> %{}
          end

        case API.call(method, params) do
          {:ok, result} ->
            Mix.shell().info(
              Jason.encode_to_iodata!(%{ok: true, result: result})
              |> IO.iodata_to_binary()
            )

          {:error, reason} ->
            Mix.shell().error(
              Jason.encode_to_iodata!(%{ok: false, error: inspect(reason)})
              |> IO.iodata_to_binary()
            )
        end
    end
  end

  defp decode_json!(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      {:ok, _} -> Mix.raise("--json must decode to a map")
      {:error, err} -> Mix.raise("Invalid JSON for --json: #{inspect(err)}")
    end
  end

  defp read_json_file!(path) do
    case FSScanner.preview(path, max_lines: 500_000) do
      {:ok, lines} ->
        content = Enum.join(List.wrap(lines), "\n")

        case Jason.decode(content) do
          {:ok, map} when is_map(map) -> map
          {:ok, _} -> Mix.raise("File JSON must be an object (map)")
          {:error, err} -> Mix.raise("Invalid JSON in file #{path}: #{inspect(err)}")
        end

      {:error, reason} ->
        Mix.raise("Failed to read file via FSScanner: #{inspect(reason)}")
    end
  end
end
