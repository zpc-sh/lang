defmodule Mix.Tasks.Lsp.Coverage do
  use Mix.Task
  @shortdoc "Report coverage of priv/lsp/specs against LSP Dispatch routes"

  @moduledoc """
  Compares JSON-LD specs (priv/lsp/specs) with handlers wired in lib/lang/lsp/dispatch.ex
  and prints a short coverage report with missing methods.

  Notes:
  - Uses Lang.Native.FSScanner for filesystem access per project guidelines.
  - Does not start the server; safe to run in CI.
  """

  alias Lang.Native.FSScanner

  @impl true
  def run(_args) do
    Mix.Task.run("loadpaths")

    spec_dir = "priv/lsp/specs"

    spec_methods = load_spec_methods(spec_dir)
    dispatch_methods = load_dispatch_methods("lib/lang/lsp/dispatch.ex")

    missing = spec_methods -- dispatch_methods
    extra = dispatch_methods -- spec_methods

    Mix.shell().info("Specs: #{length(spec_methods)}  Dispatch: #{length(dispatch_methods)}")
    Mix.shell().info("Missing in Dispatch: #{length(missing)}  (see below)")

    Enum.take(Enum.sort(missing), 100)
    |> Enum.each(&Mix.shell().info("  - #{&1}"))

    if extra != [] do
      Mix.shell().info("\nHandlers without spec: #{length(extra)}")
      Enum.take(Enum.sort(extra), 50)
      |> Enum.each(&Mix.shell().info("  ~ #{&1}"))
    end
  end

  defp load_spec_methods(dir) do
    files =
      case FSScanner.search(dir, ~S/\.(jsonld|ya?ml)$/, max_results: 100_000) do
        {:ok, results} when is_list(results) ->
          Enum.map(results, fn
            %{:path => path} -> path
            %{"path" => path} -> path
            path when is_binary(path) -> path
          end)

        _ -> []
      end

    files
    |> Enum.flat_map(fn path ->
      case FSScanner.preview(path, max_lines: 200_000) do
        {:ok, lines} ->
          content = Enum.join(List.wrap(lines), "\n")
          extract_names_from_spec(content)

        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp extract_names_from_spec(content) do
    with {:ok, json} <- Jason.decode(content) do
      names =
        case json do
          %{"name" => name} -> [name]
          list when is_list(list) -> Enum.flat_map(list, &((&1["name"] && [&1["name"]]) || []))
          _ -> []
        end

      Enum.filter(names, &is_binary/1)
    else
      _ -> []
    end
  end

  defp load_dispatch_methods(path) do
    case FSScanner.preview(path, max_lines: 200_000) do
      {:ok, lines} ->
        Enum.join(List.wrap(lines), "\n")
        |> extract_methods_from_dispatch()

      _ -> []
    end
  end

  defp extract_methods_from_dispatch(text) do
    Regex.scan(~r/"(lang\.[a-zA-Z0-9_.]+)"\s*->/u, text)
    |> Enum.map(fn [_, m] -> m end)
    |> Enum.uniq()
  end
end
