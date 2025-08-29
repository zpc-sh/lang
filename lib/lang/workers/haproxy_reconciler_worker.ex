defmodule Lang.Workers.HAProxyReconcilerWorker do
  @moduledoc """
  Reconcile HAProxy Data Plane desired state with actual configuration.

  Reads desired backends/servers from config and applies via a single
  transaction using the Data Plane API. Idempotent and safe to retry.

      config :lang, :haproxy,
        base_url: "http://haproxy-dp:5555",
        auth: {:basic, {"user", "pass"}},
        backends: %{
          "proxy_ai" => [
            %{name: "ai-1", address: "10.0.0.5", port: 4000},
            %{name: "ai-2", address: "10.0.0.6", port: 4000}
          ],
          "proxy_lsp" => [
            %{name: "lsp-1", address: "10.0.0.7", port: 4100}
          ]
        }
  """

  use Oban.Worker, queue: :metrics, max_attempts: 3
  require Logger

  alias Lang.Proxy.HAProxyDPClient, as: DP

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("Reconciling HAProxy configuration")

    req = DP.new()

    with {:ok, version} <- DP.get_version(req),
         {:ok, txn} <- DP.start_transaction(req, version) do
      try do
        :ok = ensure_backends(req, txn, desired_backends(args))
        :ok = DP.commit_transaction(req, txn)
        :ok
      catch
        :exit, reason ->
          _ = DP.abort_transaction(req, txn)
          {:error, {:txn_exit, reason}}
      rescue
        e ->
          _ = DP.abort_transaction(req, txn)
          {:error, {:txn_error, e}}
      end
    else
      {:error, reason} ->
        Logger.error("HAProxy reconcile failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  defp ensure_backends(req, txn, backends) when is_map(backends) do
    Enum.reduce_while(backends, :ok, fn {backend, servers}, _acc ->
      case DP.upsert_backend(req, txn, backend, "http") do
        :ok ->
          case ensure_servers(req, txn, backend, servers) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_servers(_req, _txn, _backend, servers) when not is_list(servers), do: :ok

  defp ensure_servers(req, txn, backend, servers) do
    Enum.reduce_while(servers, :ok, fn s, _acc ->
      case DP.upsert_server(
             req,
             txn,
             backend,
             s[:name] || s["name"],
             s[:address] || s["address"],
             s[:port] || s["port"],
             check: Map.get(s, :check, Map.get(s, "check", true)),
             weight: Map.get(s, :weight, Map.get(s, "weight", 100))
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp desired_backends(args) do
    # Allow overrides via job args; default to application config
    case args do
      %{"backends" => b} when is_map(b) ->
        b

      _ ->
        cfg = Application.get_env(:lang, :haproxy, %{})
        cfg[:backends] || %{}
    end
  end
end
