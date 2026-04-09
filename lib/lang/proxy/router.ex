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
  alias Lang.Proxy.{Pipeline, ChainConformance}

  @type result :: {:ok, any()} | {:error, integer(), String.t(), map()}

  @doc """
  Dispatches AI service requests with cost tracking.
  """
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

  @doc """
  Dispatches general AI service requests.
  """
  def dispatch(%Envelope{service: :ai, method: method, params: params, opts: opts}) do
    case AIRouter.route_request(method, params, normalize_opts(opts)) do
      {:ok, res} -> {:ok, res}
      {:error, reason} -> {:error, -32001, "AI provider error", %{reason: inspect(reason)}}
      other -> {:error, -32000, "Invalid provider response", %{result: inspect(other)}}
    end
  end

  @doc """
  Dispatches LSP service requests.
  """
  def dispatch(%Envelope{service: :lsp, method: method, params: params, opts: opts}) do
    case LSPRouter.dispatch(method, params, normalize_opts(opts)) do
      {:ok, res} -> {:ok, res}
      {:error, code, message, data} -> {:error, code, message, data}
      other -> {:error, -32000, "Invalid LSP response", %{result: inspect(other)}}
    end
  end

  @doc """
  Dispatches proxy pipeline requests.
  """
  def dispatch(%Envelope{service: :proxy, method: "pipeline.run", params: params} = env) do
    assigns = Map.get(env, :meta, %{})
    case Pipeline.run(%Envelope{env | params: params}, assigns) do
      {:ok, res} -> {:ok, %{pipeline: res}}
      {:error, code, message, data} -> {:error, code, message, data}
    end
  end

  def dispatch(%Envelope{service: :proxy, method: "pipeline.replay", params: params} = env) do
    assigns = Map.get(env, :meta, %{})
    source_pipeline_id = params["source_pipeline_id"] || params[:source_pipeline_id]

    case ChainConformance.replay(source_pipeline_id, params, assigns) do
      {:ok, replay} -> {:ok, replay}
      {:error, %{code: code, message: message, data: data}} -> {:error, code, message, data}
      {:error, reason} -> {:error, -32060, "pipeline replay failed", %{reason: inspect(reason)}}
    end
  end

  def dispatch(%Envelope{service: :proxy, method: "pipeline.conformance_report", params: params}) do
    baseline = params["baseline_pipeline_id"] || params[:baseline_pipeline_id]
    candidate = params["candidate_pipeline_id"] || params[:candidate_pipeline_id]

    case ChainConformance.report(baseline, candidate, params) do
      {:ok, report} -> {:ok, report}
      {:error, reason} -> {:error, -32061, "conformance report failed", %{reason: inspect(reason)}}
    end
  end

  @doc """
  Dispatches Telnet service requests.
  """
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

  @doc """
  Handles requests for unimplemented services.
  """
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

  # MCP service for Multi-Connection Protocol bridging
  def dispatch(%Envelope{service: :mcp, method: method, params: params, opts: opts}) do
    client_id = get_client_id(opts)

    case validate_client_id(client_id) do
      {:ok, validated_client_id} ->
        dispatch_mcp_method(method, params, Map.put(opts, :client_id, validated_client_id))

      {:error, reason} ->
        {:error, -32040, "Invalid client ID", %{reason: reason}}
    end
  end

  defp dispatch_mcp_method("connection.create", params, opts) do
    case Lang.MCP.ConnectionManager.create_connection(params, opts) do
      {:ok, connection} ->
        Lang.Events.track_event(%{
          event_type: "mcp_connection_created",
          user_id: Map.get(opts, :user_id),
          metadata: %{
            connection_id: connection.connection_id,
            client_id: Map.get(opts, :client_id)
          }
        })
        {:ok, connection}

      {:error, reason} ->
        {:error, -32041, "MCP connection creation failed", %{reason: inspect(reason)}}
    end
  end

  defp dispatch_mcp_method("connection.destroy", params, opts) do
    connection_id = Map.get(params, "connection_id")

    case Lang.MCP.ConnectionManager.destroy_connection(connection_id, opts) do
      {:ok, result} ->
        Lang.Events.track_event(%{
          event_type: "mcp_connection_destroyed",
          user_id: Map.get(opts, :user_id),
          metadata: %{
            connection_id: connection_id,
            client_id: Map.get(opts, :client_id)
          }
        })
        {:ok, result}

      {:error, reason} ->
        {:error, -32042, "MCP connection destruction failed", %{reason: inspect(reason)}}
    end
  end

  defp dispatch_mcp_method("connection.status", params, opts) do
    connection_id = Map.get(params, "connection_id")

    case Lang.MCP.ConnectionManager.get_connection_status(connection_id, opts) do
      {:ok, status} ->
        {:ok, status}

      {:error, reason} ->
        {:error, -32043, "MCP connection status query failed", %{reason: inspect(reason)}}
    end
  end

  defp dispatch_mcp_method(method, _params, _opts) do
    {:error, -32601, "MCP method not implemented", %{method: method}}
  end

  defp get_client_id(opts) do
    # Extract Client_ID from various possible sources
    cond do
      is_list(opts) ->
        Keyword.get(opts, :client_id)
      
      is_map(opts) ->
        Map.get(opts, "client_id") || Map.get(opts, :client_id)
      
      true -> nil
    end
  end

  defp validate_client_id(nil), do: {:error, "Client_ID required"}
  defp validate_client_id(client_id) when is_binary(client_id) and byte_size(client_id) > 0 do
    # Basic validation - could be enhanced with JWT verification or other auth
    {:ok, client_id}
  end
  defp validate_client_id(_), do: {:error, "Invalid Client_ID format"}
end
