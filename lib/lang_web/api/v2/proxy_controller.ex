defmodule LangWeb.Api.V2.ProxyController do
  use LangWeb, :controller

  alias Lang.Proxy.{CaptureSchema, CaptureStore, Envelope, Router}

  def call(conn, params) do
    with {:ok, env} <- Envelope.new(params),
         result <- Router.dispatch(env),
         {:ok, capture} <- persist_capture(conn, env, result, params) do
      render_proxy_result(conn, result, capture.id)
    else
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
  end

  # Existing route placeholders; keep simple wrappers.
  def issue_intent(conn, params), do: call(conn, params)
  def run_session(conn, params), do: call(conn, params)

  def get_capture(conn, %{"id" => id}) do
    case CaptureStore.get_capture(id) do
      {:ok, capture} -> json(conn, %{capture: capture})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "capture_not_found"})
    end
  end

  def find_capture(conn, params) do
    opts = [trace_id: params["trace_id"], idempotency_key: params["idempotency_key"]]

    case CaptureStore.find_capture(opts) do
      {:ok, capture} -> json(conn, %{capture: capture})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "capture_not_found"})
    end
  end

  def replay_capture(conn, %{"id" => id} = params) do
    mode = parse_mode(params["mode"])

    case CaptureStore.replay_capture(id, mode) do
      {:ok, replay} -> json(conn, %{replay: replay})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "capture_not_found"})
      {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  defp parse_mode("strict"), do: :strict
  defp parse_mode(:strict), do: :strict
  defp parse_mode(_), do: :dry

  defp persist_capture(conn, env, result, params) do
    trace_id = params["trace_id"] || get_req_header(conn, "x-trace-id") |> List.first()

    idem_key =
      params["idempotency_key"] ||
        get_req_header(conn, "idempotency-key") |> List.first()

    route_path = params["route_path"] || get_in(params, ["params", "route"]) || env.method

    CaptureStore.put_capture(%{
      trace_id: trace_id,
      idempotency_key: idem_key,
      route_path: route_path,
      dependency_refs: params["dependency_refs"] || [],
      canonical_request: CaptureSchema.canonical_request(env),
      canonical_response: CaptureSchema.canonical_response(result)
    })
  end

  defp render_proxy_result(conn, {:ok, payload}, capture_id) do
    json(conn, %{ok: true, result: payload, capture_id: capture_id})
  end

  defp render_proxy_result(conn, {:error, code, message, data}, capture_id) do
    conn
    |> put_status(:bad_request)
    |> json(%{ok: false, error: %{code: code, message: message, data: data}, capture_id: capture_id})
  end
end
