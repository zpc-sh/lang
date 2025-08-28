defmodule Nullity.CDFM.LSPProjectGenerator do
  @moduledoc """
  Project-level generator that emits handlers (via CDFM.Formats.LSP),
  plus registry and docs/lsp.md from a list of method blueprints.
  """

  alias Nullity.CDFM.Registry
  alias CDFM.Formats.LSP

  @type blueprint :: map()
  @type file_spec :: %{path: String.t(), content: iodata(), type: atom(), mode: atom(), description: String.t()}

  @doc """
  Generate all artifacts for the given method blueprints.
  """
  def generate_all(blueprints) when is_list(blueprints) do
    # 1) Handlers per blueprint
    {:ok, handler_files} =
      blueprints
      |> Enum.map(&LSP.generate(&1, []))
      |> Enum.reduce({:ok, []}, fn
        {:ok, %{files: files}}, {:ok, acc} -> {:ok, acc ++ files}
        {:error, reason}, _ -> {:error, reason}
      end)

    # 2) Registry from blueprints
    map = Registry.build(to_specs(blueprints))
    registry_file = %{
      path: "lib/lang/lsp/registry.ex",
      type: :code,
      mode: :create,
      description: "Generated LSP registry",
      content: render_registry(map)
    }

    # 3) Docs table
    docs_file = %{
      path: "docs/lsp.md",
      type: :doc,
      mode: :create,
      description: "Generated LSP documentation",
      content: render_docs(blueprints)
    }

    {:ok, %{files: handler_files ++ [registry_file, docs_file], metadata: %{count: length(blueprints)}}}
  end

  defp to_specs(blueprints) do
    Enum.map(blueprints, fn bp ->
      %{
        name: get(bp, :name),
        impl_module: get(bp, :impl_module),
        impl_function: get(bp, :impl_function) || :handle,
        impl_arity: get(bp, :impl_arity) || 2
      }
    end)
  end

  defp render_registry(map) do
    entries =
      map
      |> Enum.map(fn {name, {m, f, a}} -> "    \"#{name}\" => {#{inspect(m)}, :#{f}, #{a}}" end)
      |> Enum.join(",\n")

    """
    defmodule Lang.LSP.Registry do
      @moduledoc "Generated method registry (do not edit manually)"
      @registry %{
#{entries}
      }

      @doc "Lookup method → {module, function, arity}"
      def lookup(method), do: Map.get(@registry, method)
    end
    """
  end

  defp render_docs(blueprints) do
    rows =
      blueprints
      |> Enum.sort_by(&get(&1, :name))
      |> Enum.map(&doc_row/1)
      |> Enum.join("\n")

    """
    # LANG LSP Methods (Generated)

    | Method | Status | Priority | Description | Implementation File |
    |--------|--------|----------|-------------|---------------------|
#{rows}
    """
  end

  defp doc_row(bp) do
    name = get(bp, :name)
    status = emoji(get(bp, :derived_status) || :not_started)
    priority = get(bp, :priority) || "Medium"
    desc = get(bp, :description) || ""
    file = get(bp, :impl_file) || default_impl_file(name, get(bp, :category))
    "| `#{name}` | #{status} | #{priority} | #{desc} | `#{file}` |"
  end

  defp emoji(:implemented), do: "✅"
  defp emoji(:in_progress), do: "🚧"
  defp emoji(_), do: "❌"

  defp default_impl_file(method, category) do
    cat = category || derive_category(method)
    snake = method |> String.replace(".", "_") |> String.downcase()
    "lib/lang/lsp/#{cat}/#{snake}.ex"
  end

  defp derive_category(name) do
    case String.split(name, ".") do
      ["lang", cat | _] -> cat
      [cat | _] -> cat
      _ -> "other"
    end
  end

  defp get(map, key), do: map[key] || map[Atom.to_string(key)]
end

