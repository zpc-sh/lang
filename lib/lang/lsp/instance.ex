defmodule Lang.LSP.Instance do
  @moduledoc """
  Per-connection, in-process JSON-RPC handler for LANG methods.

  This is a lightweight proxy that avoids any shared global LSP server.
  It does not open sockets and does not register a global name.
  """

  use GenServer
  require Logger

  alias Lang.LSP.Dispatch

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    lease_ttl = instance_cfg(:lease_ttl_ms, 120_000)
    id = make_instance_id()
    epoch = System.system_time(:millisecond)

    state = %{
      cid: Map.get(opts, :cid),
      org: Map.get(opts, :org),
      scopes: Map.get(opts, :scopes),
      instance_id: id,
      epoch: epoch,
      lease_ttl_ms: lease_ttl,
      lease_deadline_ms: now_ms() + lease_ttl
    }

    Process.send_after(self(), :lease_check, lease_ttl)
    Process.send_after(self(), :watchdog, instance_cfg(:watchdog_interval_ms, 15_000))
    {:ok, state}
  end

  @doc """
  Handle a JSON-RPC payload (JSON string). Returns {:ok, json_reply | nil}.
  """
  def handle_json(pid, json) when is_binary(json) do
    GenServer.call(pid, {:handle_json, json}, 5_000)
  end

  @impl true
  def handle_call({:handle_json, json}, _from, state) do
    reply =
      with {:ok, msg} <- Jason.decode(json),
           %{} <- ensure_map(msg),
           :ok <- self_only_guard(msg, state),
           {:ok, sanitized_msg, ctx} <- secure_request(msg, state) do
        # Lease renewal on any activity; prefer explicit heartbeat but accept any request
        new_state = renew_lease(state)
        case Dispatch.process(sanitized_msg) do
          nil -> nil
          map when is_map(map) ->
            {:ok, resp} = secure_response(map, ctx)
            Jason.encode!(resp)
          other ->
            {:ok, resp} = secure_response(%{"jsonrpc" => "2.0", "id" => msg["id"], "result" => other}, ctx)
            Jason.encode!(resp)
        end
      else
        {:error, err} -> Jason.encode!(%{"jsonrpc" => "2.0", "id" => get_in_safe(json, ["id"]) || 0, "error" => %{code: -32003, message: to_string(err)}})
        _ -> nil
      end

    {:reply, {:ok, reply}, state}
  end

  defp ensure_map(%{} = m), do: m
  defp ensure_map(_), do: %{}

  defp self_only_guard(%{"params" => params}, %{cid: nil}), do: :ok
  defp self_only_guard(%{"params" => params}, %{cid: cid}) when is_map(params) do
    targets = ["client_id", "cid", "target", "target_cid", "owner_cid", "stream_owner"]
    case Enum.find_value(targets, fn k -> Map.get(params, k) end) do
      nil -> :ok
      ^cid -> :ok
      _other -> {:error, :cross_client_forbidden}
    end
  end
  defp self_only_guard(_msg, _state), do: :ok

  defp inject_identity(%{"params" => params} = msg, %{cid: cid, org: org}) do
    new_params =
      params
      |> Map.put_new("current_cid", cid)
      |> Map.put_new("current_org", org)

    Map.put(msg, "params", new_params)
  end
  defp inject_identity(msg, _), do: msg

  defp get_in_safe(json, path) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} -> get_in(map, path)
      _ -> nil
    end
  end

  defp secure_request(msg, state) do
    method = msg["method"]
    req = inject_identity(msg, state)
    case Lang.LSP.SecurityMiddleware.process_request(req, %{client_id: state.cid}) do
      {:ok, sanitized, ctx} -> {:ok, sanitized, ctx}
      {:error, reason} -> {:error, reason}
    end
  end

  defp secure_response(resp, ctx) do
    case Lang.LSP.SecurityMiddleware.process_response(resp, ctx) do
      {:ok, sanitized} -> {:ok, sanitized}
      {:error, _} -> {:ok, resp}
    end
  end

  # ---------------- Lease & Watchdog ----------------
  defp renew_lease(%{lease_ttl_ms: ttl} = state) do
    # Extend deadline on activity
    Map.put(state, :lease_deadline_ms, now_ms() + ttl)
  end

  @impl true
  def handle_info(:lease_check, state) do
    if now_ms() >= state.lease_deadline_ms do
      Logger.warn("LSP instance lease expired; terminating", instance_id: state.instance_id, cid: state.cid)
      {:stop, :lease_expired, state}
    else
      remaining = max(state.lease_deadline_ms - now_ms(), 1)
      Process.send_after(self(), :lease_check, remaining)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:watchdog, state) do
    mem = :erlang.memory(:total)
    {_, mlen} = Process.info(self(), :message_queue_len)
    mem_max = instance_cfg(:max_memory_bytes, 512 * 1024 * 1024)
    mlen_max = instance_cfg(:max_mailbox, 5_000)

    :telemetry.execute([:lang, :lsp, :instance, :watchdog], %{memory: mem, mailbox: mlen}, %{instance_id: state.instance_id, cid: state.cid})

    cond do
      mem > mem_max or mlen > mlen_max ->
        Logger.error("Instance watchdog tripped; stopping", memory: mem, mailbox: mlen, instance_id: state.instance_id)
        {:stop, :watchdog_trip, state}
      true ->
        Process.send_after(self(), :watchdog, instance_cfg(:watchdog_interval_ms, 15_000))
        {:noreply, state}
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
  defp make_instance_id, do: "inst_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  defp instance_cfg(key, default) do
    case Application.get_env(:lang, :lsp_instance) do
      m when is_list(m) -> Keyword.get(m, key, default)
      m when is_map(m) -> Map.get(m, key, default)
      _ -> default
    end
  end
end
