defmodule LangWeb.DevLspAdminController do
  use LangWeb, :controller
  import Ash.Query

  def clients(conn, _params) do
    data =
      try do
        Lang.LSP.PhoenixIntegration.list_clients()
        |> Enum.map(fn {socket, pid, info} ->
          %{
            socket: inspect(socket),
            pid: inspect(pid),
            info: info
          }
        end)
      rescue
        _ -> []
      end

    json(conn, %{count: length(data), clients: data})
  end

  def methods(conn, params) do
    window = Map.get(params, "minutes", "30") |> parse_int(30)
    from = DateTime.add(DateTime.utc_now(), -window * 60, :second)

    methods =
      case Lang.LSP.Events.MetricEvent |> filter(at >= ^from) |> Ash.read() do
        {:ok, events} ->
          events
          |> Enum.filter(&match?(%{event: :request}, &1) or match?(%{event: :response}, &1))
          |> Enum.map(&get_in(&1, [:metadata, :method]))
          |> Enum.reject(&is_nil/1)
          |> Enum.group_by(& &1)
          |> Enum.map(fn {m, list} -> %{method: m, count: length(list)} end)
          |> Enum.sort_by(& &1.count, :desc)

        _ -> []
      end

    json(conn, %{window_minutes: window, methods: methods})
  end

  def heartbeat(conn, _params) do
    data =
      try do
        list = Lang.LSP.PhoenixIntegration.list_clients()
        %{time: DateTime.utc_now(), count: length(list)}
      rescue
        _ -> %{time: DateTime.utc_now(), count: 0}
      end

    json(conn, data)
  end

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      _ -> default
    end
  end


  def tap(conn, %{"id" => client_id} = params) do
    attrs = %{
      "active" => Map.get(params, "active", true),
      "methods" => (params["methods"] and Enum.join(List.wrap(params["methods"]), ",")) || Map.get(params, "methods_csv", ""),
      "max" => parse_int(Map.get(params, "max", "500"), 500)
    }
    case Lang.Dev.LSPTracer.configure(client_id, attrs) do
      {:ok, rec} -> json(conn, rec)
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
  end

  def trace(conn, %{"id" => client_id} = params) do
    opts = %{
      method: Map.get(params, "method"),
      since: Map.get(params, "since"),
      limit: parse_int(Map.get(params, "limit", "200"), 200)
    }
    case Lang.Dev.LSPTracer.list_traces(client_id, opts) do
      {:ok, list} -> json(conn, %{client_id: client_id, traces: list})
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
  end

end
