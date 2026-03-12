defmodule Lang.Workers.LSPPrewarmWorker do
  use Oban.Worker, queue: :lsp, max_attempts: 1

  @impl true
  def perform(%Oban.Job{args: %{"domains" => domains}}) when is_list(domains) do
    Enum.each(domains, fn d -> Lang.LSP.Prewarm.prewarm_domain(to_domain(d)) end)
    :ok
  end
  def perform(_), do: :ok

  defp to_domain(d) when is_atom(d), do: d
  defp to_domain(d) when is_binary(d) do
    case d do
      "core" -> :core
      "doc_io" -> :doc_io
      "completion" -> :completion
      "code_nav" -> :code_nav
      "lang_custom" -> :lang_custom
      _ -> :core
    end
  end
end

