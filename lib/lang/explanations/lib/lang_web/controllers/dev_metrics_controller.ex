defmodule LangWeb.DevMetricsController do
  use LangWeb, :controller
  import Ash.Query

  def summary(conn, _params) do
    case Lang.Dev.Metrics.summary() do
      {:ok, %{counts: _} = data} -> json(conn, data)
      %{counts: _} = data -> json(conn, data)
      {:error, reason} -> conn |> put_status(:service_unavailable) |> json(%{error: to_string(reason)})
    end
  end

  def lsp(conn, params) do
    window = Map.get(params, "minutes", "15") |> parse_int(15)
    from = DateTime.add(DateTime.utc_now(), -window * 60, :second)

    counts = %{
      diagnostics: count_since(Lang.LSP.Events.DiagnosticEvent, from),
      completions: count_since(Lang.LSP.Events.CompletionEvent, from)
    }

    json(conn, %{window_minutes: window, counts: counts})
  end

  def nif(conn, _params) do
    res = %{
      fs_scanner: loaded?(Lang.Native.FSScanner),
      lang_perf: loaded?(Lang.Native.PerfEngine),
      tree_parser: loaded?(Lang.Native.TreeParser),
      lang_parser: loaded?(Lang.Native.LangParser)
    }
    json(conn, res)
  end

  defp count_since(resource, from_dt) do
    case resource |> filter(at >= ^from_dt) |> Ash.read() do
      {:ok, list} when is_list(list) -> length(list)
      _ -> 0
    end
  end

  defp loaded?(mod) do
    case Code.ensure_loaded(mod) do
      {:module, _} -> true
      _ -> false
    end
  end

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      _ -> default
    end
  end
end
