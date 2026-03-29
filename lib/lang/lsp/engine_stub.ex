defmodule Lang.LSP.EngineStub do
  @moduledoc """
  Development stub for an Engine-style LSP provider.

  Uses local native capabilities to simulate responses where possible.
  Configure via:
      config :lang, :lsp_engine_module, Lang.LSP.EngineStub
  """

  @behaviour Lang.LSP.EngineBehaviour

  @impl true
  def symbols(%{"file_path" => file_path}) when is_binary(file_path) do
    case Lang.Native.TreeParser.extract_symbols(file_path) do
      {:ok, syms} ->
        {:ok,
         Enum.map(syms, fn s ->
           loc = s["location"] || %{}
           row = loc["row"] || 0
           col = loc["column"] || 0
           %{
             name: s["name"],
             kind: s["symbol_type"] || "function",
             range: %{start: %{line: row, character: col}, end: %{line: row, character: col}},
             uri: "file://" <> file_path,
             file_path: file_path
           }
         end)}
      error -> error
    end
  end

  def symbols(_), do: {:ok, []}

  @impl true
  def references(_params), do: {:ok, []}

  @impl true
  def definitions(_params), do: {:ok, []}

  @impl true
  def hover(_params), do: {:ok, %{contents: []}}

  @impl true
  def semantic_tokens(_params), do: {:ok, %{data: []}}
end

