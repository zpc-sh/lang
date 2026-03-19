defmodule Lang.LSP.Prewarm do
  @moduledoc """
  Lightweight pre-warm hooks for adjacent domains. Keep fast and non-blocking.

  Long pre-warm routines should be queued via Oban (see LSPPrewarmWorker).
  """

  require Logger

  def prewarm_domain(:core) do
    safe(fn -> Code.ensure_loaded(Lang.LSP.Spec) end)
  end

  def prewarm_domain(:doc_io) do
    safe(fn -> Code.ensure_loaded(Lang.LSP.Document) end)
  end

  def prewarm_domain(:completion) do
    safe(fn ->
      Code.ensure_loaded(Lang.LSP.Handlers.Completion)
      Code.ensure_loaded(Lang.TextIntelligence.ParserRegistry)
    end)
  end

  def prewarm_domain(:code_nav) do
    safe(fn -> Code.ensure_loaded(Lang.TextIntelligence.SymbolAnalyzer) end)
  end

  def prewarm_domain(:lang_custom) do
    safe(fn -> Code.ensure_loaded(Lang.LSP.Dispatch) end)
  end

  # Generative is expensive and unrelated; do not prewarm implicitly
  def prewarm_domain(:generative), do: :ok

  def prewarm_domain(_), do: :ok

  defp safe(fun) do
    try do
      fun.()
      :ok
    rescue
      e -> Logger.debug("prewarm error", error: inspect(e))
    catch
      _ -> :ok
    end
  end
end
