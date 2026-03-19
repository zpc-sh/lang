defmodule Lang.LSP.EngineBehaviour do
  @moduledoc """
  Behaviour contract for Engine LSP integration (injects into VM).

  Providers implementing this behaviour can be configured via:
      config :lang, :lsp_engine_module, YourEngineModule
  """

  @callback symbols(map()) :: {:ok, [map()]} | {:error, term()}
  @callback references(map()) :: {:ok, [map()]} | {:error, term()}
  @callback definitions(map()) :: {:ok, [map()]} | {:error, term()}
  @callback hover(map()) :: {:ok, map()} | {:error, term()}
  @callback semantic_tokens(map()) :: {:ok, map()} | {:error, term()}
end

