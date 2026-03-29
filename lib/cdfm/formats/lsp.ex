defmodule CDFM.Formats.LSP do
  @moduledoc """
  Minimal LSP format generator: emits a handler skeleton and contributes to a
  code registry and docs. Built on the CDFM BaseGenerator behaviour.
  """
  use CDFM.Formats.BaseGenerator

  @impl true
  def format_name, do: :lsp

  @impl true
  def installation_requirements do
    %{elixir: Version.parse!(System.version()), requires: [:ash, :phoenix], optional: [:oban]}
  end

  @impl true
  def format_metadata do
    %{emits: [:handler, :doc_entry], behaviour: "Lang.LSP.Handler"}
  end

  @impl true
  def generate(blueprint, _opts) do
    method = blueprint[:name] || blueprint["name"]
    category = blueprint[:category] || blueprint["category"] || derive_category(method)
    impl_file = blueprint[:impl_file] || default_impl_file(method, category)
    mod = blueprint[:impl_module] || default_impl_module(method)
    fun = blueprint[:impl_function] || :handle
    arity = blueprint[:impl_arity] || 2

    files = [
      generate_file(
        impl_file,
        handler_template(mod, method, fun, arity, blueprint[:description] || "")
      )
    ]

    {:ok, %{files: files, metadata: %{method: method, module: mod}}}
  end

  defp handler_template(mod, method, fun, arity, desc) do
    """
    defmodule #{mod} do
      @moduledoc #{inspect(desc)}
      @behaviour Lang.LSP.Handler
      @lsp_method #{inspect(method)}

      @impl true
      def method, do: @lsp_method

      @impl true
      def #{fun}(params, ctx) when is_map(params) and is_map(ctx) do
        # TODO: implement
        {:error, :not_implemented}
      end
    end
    """
  end

  defp default_impl_file(method, category) do
    snake = method |> String.replace(".", "_") |> String.downcase()
    "lib/lang/lsp/#{category}/#{snake}.ex"
  end

  defp default_impl_module(method) do
    parts = String.split(method, ".")
    mod_parts = Enum.map(parts, &Macro.camelize/1)
    Module.concat([Lang, LSP | Enum.map(mod_parts, &String.to_atom/1)])
  end

  defp derive_category(nil), do: "other"

  defp derive_category(name) do
    case String.split(name, ".") do
      ["lang", cat | _] -> cat
      [cat | _] -> cat
      _ -> "other"
    end
  end
end
