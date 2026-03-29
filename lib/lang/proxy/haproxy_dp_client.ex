defmodule Lang.Proxy.HAProxyDPClient do
  @moduledoc """
  HAProxy Data Plane API client using Req (dynamic config, transactions).

  Configure via:
      config :lang, :haproxy,
        base_url: "http://127.0.0.1:5555",
        auth: {:basic, {"user", "pass"}},
        verify: :verify_none
  """

  @type req :: Req.Request.t()
  @type txn_id :: String.t()

  def new(opts \\ []) do
    cfg = Application.get_env(:lang, :haproxy, %{})
    base_url = Keyword.get(opts, :base_url, cfg[:base_url] || "http://127.0.0.1:5555")
    auth = Keyword.get(opts, :auth, cfg[:auth])
    verify = Keyword.get(opts, :verify, cfg[:verify])

    req = Req.new(base_url: base_url, auth: auth)
    req = if verify, do: Req.merge(req, ssl: [verify: verify]), else: req
    req
  end

  # === Versioned transaction lifecycle ===

  @spec get_version(req()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_version(req \\ new()) do
    request(req, :get, "/v2/services/haproxy/configuration/version")
    |> case do
      {:ok, %{"version" => v}} when is_integer(v) -> {:ok, v}
      {:ok, body} -> {:error, {:unexpected_body, body}}
      other -> other
    end
  end

  @spec start_transaction(req(), non_neg_integer()) :: {:ok, txn_id()} | {:error, term()}
  def start_transaction(req \\ new(), version) when is_integer(version) do
    request(req, :post, "/v2/services/haproxy/transactions?version=#{version}")
    |> case do
      {:ok, %{"id" => id}} -> {:ok, id}
      other -> other
    end
  end

  @spec commit_transaction(req(), txn_id()) :: :ok | {:error, term()}
  def commit_transaction(req \\ new(), txn_id) do
    case request(req, :put, "/v2/services/haproxy/transactions/#{txn_id}") do
      {:ok, _} -> :ok
      other -> other
    end
  end

  @spec abort_transaction(req(), txn_id()) :: :ok | {:error, term()}
  def abort_transaction(req \\ new(), txn_id) do
    case request(req, :delete, "/v2/services/haproxy/transactions/#{txn_id}") do
      {:ok, _} -> :ok
      other -> other
    end
  end

  # === Upserts ===

  @spec upsert_backend(req(), txn_id(), String.t(), String.t()) :: :ok | {:error, term()}
  def upsert_backend(req \\ new(), txn_id, name, mode \\ "http") do
    body = %{name: name, mode: mode}
    path = "/v2/services/haproxy/configuration/backends?transaction_id=#{txn_id}"
    upsert(req, path, body, fn ->
      put_path = path <> "&replace=true"
      request(req, :post, put_path, body)
    end)
  end

  @spec upsert_server(req(), txn_id(), String.t(), String.t(), String.t(), pos_integer(), keyword()) ::
          :ok | {:error, term()}
  def upsert_server(req \\ new(), txn_id, backend, name, address, port, opts \\ []) do
    body = %{
      name: name,
      address: address,
      port: port,
      check: if(Keyword.get(opts, :check, true), do: "enabled", else: "disabled"),
      weight: Keyword.get(opts, :weight, 100)
    }

    base = "/v2/services/haproxy/configuration/servers?backend=#{backend}&transaction_id=#{txn_id}"
    upsert(req, base, body, fn ->
      # Replace existing server
      request(req, :put, base <> "&name=#{name}", body)
    end)
  end

  @spec upsert_bind(req(), txn_id(), String.t(), map()) :: :ok | {:error, term()}
  def upsert_bind(req \\ new(), txn_id, frontend, bind_spec) when is_map(bind_spec) do
    path = "/v2/services/haproxy/configuration/binds?frontend=#{frontend}&transaction_id=#{txn_id}"
    upsert(req, path, bind_spec, fn -> request(req, :post, path <> "&replace=true", bind_spec) end)
  end

  # === Low-level helpers ===

  defp upsert(req, path, body, replace_fun) do
    case request(req, :post, path, body) do
      {:ok, _} -> :ok
      {:error, {:http_error, 409, _}} ->
        case replace_fun.() do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} -> {:error, reason}
    end
  end

  defp request(req, method, path, body \\ nil) do
    opts = [method: method, url: path] ++ (if body, do: [json: body], else: [])

    try do
      case Req.request(req, opts) do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> {:ok, body}
        {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
        {:error, reason} -> {:error, reason}
      end
    rescue
      e -> {:error, e}
    end
  end
end
