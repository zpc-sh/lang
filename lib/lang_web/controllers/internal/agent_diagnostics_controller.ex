defmodule LangWeb.Internal.AgentDiagnosticsController do
  use LangWeb, :controller
  alias Nullity.CDFM.Adapters.FileAdapter.FSScanner, as: FileAdapter

  @doc """
  Accept signed agent diagnostics as JSON.

  Security:
  - HMAC signature in header "x-signature" computed over Jason.encode!(params)
    using the shared secret AGENT_DIAGNOSTICS_HMAC_SECRET.
  - Returns 401 if signature missing or invalid.
  """
  def create(conn, params) do
    with {:ok, _} <- verify_signature(conn, params),
         :ok <- enforce_rate_limit(conn),
         {:ok, path} <- persist_payload(params) do
      json(conn |> put_status(:accepted), %{
        status: "accepted",
        saved: path,
        received_at: DateTime.utc_now()
      })
    else
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid_signature"})

      {:error, :rate_limited} ->
        conn |> put_status(:too_many_requests) |> json(%{error: "rate_limited"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "persist_failed", reason: inspect(reason)})
    end
  end

  defp verify_signature(conn, params) do
    secret = System.get_env("AGENT_DIAGNOSTICS_HMAC_SECRET")
    sig = get_req_header(conn, "x-signature") |> List.first()

    if is_binary(secret) and byte_size(secret) > 0 and is_binary(sig) do
      payload = Jason.encode!(params)
      mac = :crypto.mac(:hmac, :sha256, secret, payload)
      sig_hex = Base.encode16(mac, case: :lower)
      sig_b64 = Base.encode64(mac)

      if sig in [sig_hex, "sha256=" <> sig_hex, sig_b64] do
        {:ok, :valid}
      else
        {:error, :unauthorized}
      end
    else
      {:error, :unauthorized}
    end
  end

  defp enforce_rate_limit(conn) do
    ip = conn.remote_ip |> Tuple.to_list() |> Enum.join(".")
    config = %{max_requests: 30, window_seconds: 60, burst_allowance: 5}

    case Lang.Security.RateLimiter.check_with_config("ip:" <> ip, "internal_diagnostics", config) do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, :rate_limited}
      other -> other
    end
  end

  defp persist_payload(params) do
    ts = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.replace(~r/[:\+]/, "")
    path = Path.join(["priv/secret", "agent_diagnostics_" <> ts <> ".json"])
    content = Jason.encode!(params, pretty: true)

    case FileAdapter.write(path, content) do
      :ok -> {:ok, path}
      {:ok, _} -> {:ok, path}
      other -> other
    end
  end
end
