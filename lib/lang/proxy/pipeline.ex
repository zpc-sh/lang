defmodule Lang.Proxy.Pipeline do
  @moduledoc """
  Proxy pipeline executor. Executes a sequence of hops (service/method/params)
  using the existing Router, enforcing policy/heuristics per hop.

  Envelope format example:
    %{
      v: 1,
      service: :proxy,
      method: "pipeline.run",
      params: %{
        route: [
          %{service: "lsp", method: "lsp.bootstrap_ssh", params: %{...}},
          %{service: "lsp", method: "lsp.symbols", params: %{file_path: "/..."}}
        ]
      }
    }
  """

  alias Lang.Proxy.{Envelope, Heuristics, Policy, Intent, StreamBridge}

  @type hop :: %{required(:service) => String.t() | atom(), required(:method) => String.t(), optional(:params) => map()}

  @doc """
  Runs a proxy pipeline, executing a sequence of hops.
  """
  @spec run(Envelope.t(), map()) :: {:ok, [map()]} | {:error, integer(), String.t(), map()}
  def run(%Envelope{params: %{"route" => route} = params} = _env, assigns) when is_list(route) do
    pipeline_id = params["pipeline_id"] || gen_id()
    do_run(route, Map.put(assigns, :pipeline_id, pipeline_id), [], %{})
  end

  def run(_env, _assigns), do: {:error, -32602, "invalid route", %{}}

  defp do_run([], _assigns, acc, _ctx), do: {:ok, Enum.reverse(acc)}

  defp do_run([hop | rest], assigns, acc, ctx) do
    hop = normalize_hop(hop)
    bound_params = bind_params(Map.get(hop, :params, %{}), ctx)
    pipeline_id = assigns[:pipeline_id]
    hop_uid = hop[:hop_uid] || hop["hop_uid"] || gen_id()
    merged_params =
      bound_params
      |> Map.put_new("pipeline_id", pipeline_id)
      |> Map.put_new("hop_uid", hop_uid)
    env = to_envelope(%{hop | params: merged_params})

    with :ok <- Policy.authorize(env, assigns),
         :ok <- Heuristics.precheck(env, assigns),
         :ok <- maybe_require_intent(env, assigns) do
      started = System.monotonic_time()
      pipeline_id = assigns[:pipeline_id]
      StreamBridge.hop_start(pipeline_id, prune(env))
      timeout = hop[:timeout_ms] || hop["timeout_ms"] || Application.get_env(:lang, :proxy_hop_timeout_ms, 5_000)
      retries = hop[:retries] || hop["retries"] || 0
      backoff = hop[:backoff_ms] || hop["backoff_ms"] || 0

      case dispatch_with_retry(env, timeout, retries, backoff) do
        {:ok, res} ->
          stopped = System.monotonic_time()
          :telemetry.execute([:lang, :proxy, :hop, :stop], %{duration: stopped - started}, %{hop: prune(env)})
          StreamBridge.hop_stop(pipeline_id, prune(env), res)
          new_ctx = Map.put(ctx, "prev", %{"result" => res, "hop" => prune(env)})
          do_run(rest, assigns, [%{result: res, hop: prune(env)} | acc], new_ctx)

        {:error, code, message, data} ->
          StreamBridge.hop_error(pipeline_id, prune(env), code, message, data)
          {:error, code, message, Map.put(data || %{}, :hop, prune(env))}
      end
    else
      {:error, {:policy_denied, reason}} -> {:error, -32040, "policy denied", %{reason: reason, hop: prune(env)}}
      {:error, {:heuristic_block, reason}} -> {:error, -32041, "heuristic block", %{reason: reason, hop: prune(env)}}
      {:error, :intent_required} -> {:error, -32042, "intent required", %{hop: prune(env)}}
      {:error, :invalid_intent} -> {:error, -32043, "invalid intent", %{hop: prune(env)}}
      other -> {:error, -32602, "invalid hop", %{reason: inspect(other), hop: prune(env)}}
    end
  end

  defp to_envelope(%{service: s, method: m} = hop) do
    %Lang.Proxy.Envelope{v: 1, service: normalize_service(s), method: m, params: Map.get(hop, :params, %{}), opts: %{}, meta: %{}, stream?: false}
  end

  defp normalize_service(s) when is_atom(s), do: s
  defp normalize_service(s) when is_binary(s), do: String.to_atom(String.downcase(s))

  defp prune(%{service: s, method: m, params: params}) do
    base = %{service: s, method: m}
    case params do
      %{"hop_uid" => uid} when is_binary(uid) -> Map.put(base, :uid, uid)
      %{:hop_uid => uid} when is_binary(uid) -> Map.put(base, :uid, uid)
      _ -> base
    end
  end

  defp normalize_hop(h) when is_map(h) do
    # accept string keys and atoms
    h
    |> Enum.into(%{}, fn {k, v} -> {normalize_key(k), v} end)
  end

  defp normalize_key(k) when is_atom(k), do: k
  defp normalize_key(k) when is_binary(k), do: String.to_atom(k)

  defp maybe_require_intent(env, assigns) do
    sensitive? = sensitive_op?(env)
    require? = Application.get_env(:lang, :require_intent_for_sensitive, false)

    cond do
      not sensitive? -> :ok
      require? == false -> :ok
      true ->
        case env.params["intent"] do
          tok when is_binary(tok) ->
            case Intent.verify(tok) do
              {:ok, claims} ->
                cond do
                  claims["org_id"] != (assigns[:current_org] && assigns.current_org.id) -> {:error, :invalid_intent}
                  not scope_allowed?(claims, env) -> {:error, :invalid_intent}
                  true -> :ok
                end
              {:error, _} -> {:error, :invalid_intent}
            end
          _ -> {:error, :intent_required}
        end
    end
  end

  defp sensitive_op?(%{service: s, method: m}) do
    s in [:ssh, :fs, :telnet] or (s == :lsp and to_string(m) in ["lsp.bootstrap", "lsp.bootstrap_ssh"]) 
  end

  defp scope_allowed?(%{"scope" => scopes}, %{service: s, method: m}) when is_list(scopes) do
    required = required_scope(s, to_string(m))
    required == nil or required in scopes
  end
  defp scope_allowed?(_, _), do: false

  defp required_scope(:ssh, _), do: "ssh:exec"
  defp required_scope(:fs, _), do: "fs:access"
  defp required_scope(:telnet, _), do: "ssh:bootstrap"
  defp required_scope(:lsp, method) when method in ["lsp.bootstrap", "lsp.bootstrap_ssh"], do: "ssh:bootstrap"
  defp required_scope(_, _), do: nil

  defp gen_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  # --- timeout & retry helpers ---
  defp dispatch_with_retry(env, timeout, retries, backoff_ms) do
    case dispatch_with_timeout(env, timeout) do
      {:ok, _} = ok -> ok
      {:error, :timeout} ->
        if retries > 0 do
          if backoff_ms > 0, do: Process.sleep(backoff_ms)
          dispatch_with_retry(env, timeout, retries - 1, backoff_ms)
        else
          {:error, -32050, "hop timeout", %{}}
        end

      {:error, code, msg, data} -> {:error, code, msg, data}
    end
  end

  defp dispatch_with_timeout(env, timeout) do
    task = Task.async(fn -> Lang.Proxy.Router.dispatch(env) end)
    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, res} -> res
      nil -> {:error, :timeout}
      _ -> {:error, :timeout}
    end
  end

  # --- output binding ---
  defp bind_params(params, ctx) when is_map(params) do
    Enum.into(params, %{}, fn {k, v} -> {k, bind_value(v, ctx)} end)
  end

  defp bind_value(v, ctx) when is_binary(v) do
    case v do
      <<"${", rest::binary>> ->
        if String.ends_with?(rest, "}") do
          path = String.trim_trailing(rest, "}") |> String.split(".")
          get_in(ctx, path_to_access(path)) || v
        else
          v
        end
      _ -> v
    end
  end

  defp bind_value(%{} = m, ctx), do: bind_params(m, ctx)
  defp bind_value(list, ctx) when is_list(list), do: Enum.map(list, &bind_value(&1, ctx))
  defp bind_value(v, _), do: v

  defp path_to_access(["prev" | rest]), do: ["prev" | rest]
  defp path_to_access(other), do: other
end
