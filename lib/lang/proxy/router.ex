defmodule Lang.Proxy.Router do
  @moduledoc """
  Primary proxy router. Dispatches proxy envelopes to underlying services.

  Services supported initially:
  - :ai -> Lang.Providers.Router
  Additional services can be added incrementally (e.g., :lsp, :mcp).
  """

  alias Lang.Proxy.Envelope
  alias Lang.Providers.Router, as: AIRouter
  alias Lang.Proxy.LSPRouter
  alias Lang.Proxy.Adapters.Telnet
  alias Lang.Proxy.Adapters.SSH
  alias Lang.Proxy.Pipeline

  @type result :: {:ok, any()} | {:error, integer(), String.t(), map()}

  @spec dispatch(Envelope.t()) :: result()
  def dispatch(%Envelope{service: :ai, method: "lang.chat.send_with_cost_tracking", params: params, opts: opts}) do
    cost_opts = Map.get(params, "cost_options") || %{}
    priority =
      case to_string(Map.get(cost_opts, "provider_optimization", "balanced")) do
        "cost_optimized" -> :cost_first
        "quality_first" -> :quality_first
        _ -> :balanced
      end

    route_opts = normalize_opts(opts) ++ [cost_priority: priority]

    # Hard budget preflight if limit provided
    limit = Map.get(cost_opts, "limit")
    if is_number(limit) do
      provider = predicted_provider(priority)
      predicted = AIRouter.estimate_cost("lang.chat.send_with_cost_tracking", params, provider)
      if is_number(predicted) and predicted > limit do
        return = {:error, -32030, "budget exceeded", %{predicted_cost: predicted, limit: limit}}
        return
      else
        :ok
      end
    else
      :ok
    end
    |> case do
      :ok -> :ok
      err -> err
    end

    case AIRouter.route_request("lang.chat.send_with_cost_tracking", params, route_opts) do
      {:ok, res} ->
        Lang.Events.track_event(%{
          event_type: "chat_send_with_cost_tracking",
          metadata: %{
            limit: Map.get(cost_opts, "limit"),
            provider_optimization: Map.get(cost_opts, "provider_optimization")
          }
        })

        {:ok, res}

      {:error, reason} ->
        {:error, -32001, "AI provider error", %{reason: inspect(reason)}}
    end
  end

  def dispatch(%Envelope{service: :ai, method: method, params: params, opts: opts}) do
    case AIRouter.route_request(method, params, normalize_opts(opts)) do
      {:ok, res} -> {:ok, res}
      {:error, reason} -> {:error, -32001, "AI provider error", %{reason: inspect(reason)}}
      other -> {:error, -32000, "Invalid provider response", %{result: inspect(other)}}
    end
  end

  def dispatch(%Envelope{service: :lsp, method: method, params: params, opts: opts}) do
    case LSPRouter.dispatch(method, params, normalize_opts(opts)) do
      {:ok, res} -> {:ok, res}
      {:error, code, message, data} -> {:error, code, message, data}
      other -> {:error, -32000, "Invalid LSP response", %{result: inspect(other)}}
    end
  end

  def dispatch(%Envelope{service: :proxy, method: "pipeline.run", params: params} = env) do
    assigns = Map.get(env, :meta, %{})
    case Pipeline.run(%Envelope{env | params: params}, assigns) do
      {:ok, res} -> {:ok, %{pipeline: res}}
      {:error, code, message, data} -> {:error, code, message, data}
    end
  end

  def dispatch(%Envelope{service: :telnet, method: "telnet.script", params: params}) do
    with {:ok, host} <- fetch_str(params, "host"),
         {:ok, port} <- fetch_int(params, "port"),
         {:ok, script} <- fetch_script(params) do
      case Telnet.run_script(host, port, script, timeout: 5_000) do
        {:ok, out} -> {:ok, out}
        {:error, :host_not_allowed} -> {:error, -32010, "host not allowed", %{}}
        {:error, :timeout} -> {:error, -32011, "telnet timeout", %{}}
        {:error, reason} -> {:error, -32012, "telnet error", %{reason: inspect(reason)}}
      end
    else
      {:error, {:bad_param, f}} -> {:error, -32602, "invalid params", %{field: f}}
      other -> {:error, -32602, "invalid params", %{reason: inspect(other)}}
    end
  end

  def dispatch(%Envelope{service: svc}) do
    {:error, -32601, "Service not implemented", %{service: svc}}
  end

  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts(_), do: []

  defp predicted_provider(:cost_first), do: :xai
  defp predicted_provider(:quality_first), do: :anthropic
  defp predicted_provider(_), do: :openai

  defp fetch_str(params, key) do
    case params[key] do
      s when is_binary(s) and byte_size(s) > 0 -> {:ok, s}
      _ -> {:error, {:bad_param, key}}
    end
  end

  defp fetch_int(params, key) do
    case params[key] do
      i when is_integer(i) and i > 0 and i < 65536 -> {:ok, i}
      _ -> {:error, {:bad_param, key}}
    end
  end

  defp fetch_script(params) do
    case params["script"] do
      list when is_list(list) ->
        steps = Enum.map(list, &coerce_step/1)
        if Enum.all?(steps, &match?({:ok, _}, &1)), do: {:ok, Enum.map(steps, fn {:ok, v} -> v end)}, else: {:error, {:bad_param, "script"}}

      _ -> {:error, {:bad_param, "script"}}
    end
  end

  defp coerce_step(%{"send" => line}) when is_binary(line), do: {:ok, {:send, line}}
  defp coerce_step(%{"expect" => pattern}) when is_binary(pattern), do: {:ok, {:expect, pattern}}
  defp coerce_step(%{"expect" => pattern, "timeout" => t}) when is_binary(pattern) and is_integer(t), do: {:ok, {:expect, pattern, t}}
  defp coerce_step(_), do: {:error, :invalid}

  # SSH service for secure remote execution
  def dispatch(%Envelope{service: :ssh, method: "ssh.exec", params: params}) do
    with {:ok, host} <- fetch_str(params, "host"),
         {:ok, cmd} <- fetch_str(params, "cmd"),
         {:ok, user} <- fetch_str(params, "user") do
      port = params["port"] || 22
      priv_key = params["priv_key"]
      known_hosts = params["known_hosts"]
      opts = [user: user, port: port] ++ (if is_binary(priv_key), do: [priv_key: priv_key], else: []) ++ (if is_binary(known_hosts), do: [known_hosts: known_hosts], else: [])

      case SSH.exec(host, cmd, opts) do
        {:ok, res} -> {:ok, res}
        {:error, :timeout} -> {:error, -32021, "ssh timeout", %{}}
        {:error, reason} -> {:error, -32022, "ssh error", %{reason: inspect(reason)}}
      end
    else
      {:error, {:bad_param, f}} -> {:error, -32602, "invalid params", %{field: f}}
      other -> {:error, -32602, "invalid params", %{reason: inspect(other)}}
    end
  end
end
