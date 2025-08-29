defmodule Lang.Workers.AgentTaskWorker do
  @moduledoc """
  Generic Agent task worker. Queues agent-related maintenance/metrics work
  that isn't implemented synchronously.
  """
  use Oban.Worker, queue: :agent, max_attempts: 5

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => action} = args}) do
    measurements = %{system_time: System.system_time()}
    metadata = telemetry_meta(action, args)

    :telemetry.span([:lang, :agent_task], measurements, metadata, fn ->
      case validate_args(action, args) do
        :ok ->
          try do
            Logger.info("AgentTaskWorker running", action: action, args: redacted_args(args))

            case handle_action(action, args) do
              :ok ->
                :telemetry.execute(
                  [:lang, :agent_task, :result],
                  %{count: 1},
                  Map.put(metadata, :outcome, :ok)
                )

                {:ok, Map.put(metadata, :status, :ok)}

              {:error, reason} ->
                :telemetry.execute(
                  [:lang, :agent_task, :result],
                  %{count: 1},
                  Map.put(metadata, :outcome, :error)
                )

                raise "agent task failed: #{inspect(reason)}"
            end
          rescue
            e ->
              Logger.error("AgentTaskWorker failed", action: action, error: inspect(e))
              {:error, Map.put(metadata, :status, :error)}
          end

        {:error, reason} ->
          Logger.warning("AgentTaskWorker validation failed",
            action: action,
            reason: inspect(reason)
          )

          :telemetry.execute(
            [:lang, :agent_task, :result],
            %{count: 1},
            Map.put(metadata, :outcome, :invalid)
          )

          {:ok, Map.put(metadata, :status, :invalid)}
      end
    end)
    |> case do
      {:ok, _meta} -> :ok
      {:error, _meta} -> :ok
    end
  end

  defp handle_action("behavior_baseline", %{"params" => params}) do
    agent_id = params["agent_id"]
    baseline_data = Map.get(params, "baseline_data") || %{}
    context = Map.drop(params, ["agent_id", "baseline_data"])

    case Lang.Agent.Behavioral.baseline(agent_id, baseline_data, context) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp handle_action("anomaly_score", %{"params" => params}) do
    agent_id = params["agent_id"]

    case Lang.Agent.Security.scan(agent_id, %{}) do
      {:ok, result} ->
        _ =
          Lang.Agent.Behavioral.record_anomaly_sample(agent_id, %{strength: result.anomaly_score})

        :ok

      {:error, _} ->
        :ok
    end
  end

  defp handle_action("trust_level", %{"params" => params}) do
    agent_id = params["agent_id"]
    threshold = parse_float(params["threshold"]) || 0.0

    with {:ok, status} <- Lang.Agent.Lifecycle.get_status(agent_id) do
      trust =
        case status[:trust_score] do
          %Decimal{} = d -> Decimal.to_float(d)
          n when is_number(n) -> n * 1.0
          _ -> 0.0
        end

      _ =
        Lang.Events.Agent.track_trust_update(agent_id, trust, trust, "check", %{
          threshold: threshold
        })

      if trust < threshold do
        Logger.warning("Agent trust below threshold",
          agent_id: agent_id,
          trust: trust,
          threshold: threshold
        )
      end

      :ok
    else
      _ -> :ok
    end
  end

  defp handle_action("audit_trail", %{"params" => params}) do
    agent_id = params["agent_id"]
    _ = Lang.Agent.Audit.get_audit_trail(agent_id, %{})
    :ok
  end

  defp handle_action("track_usage", %{"params" => params}) do
    agent_id = params["agent_id"]

    case Lang.Agent.Supervisor.get_agent_status(agent_id) do
      {:ok, status} ->
        _ = Lang.Events.Agent.track_resource_usage(agent_id, :memory_mb, status.memory_mb, %{})
        :ok

      _ ->
        :ok
    end
  end

  defp handle_action("limit_resources", %{"params" => params}) do
    agent_id = params["agent_id"]
    limits = params["resource_limits"] || %{}

    case Lang.Agent.Resources.limit_resources(agent_id, limits) do
      :ok -> :ok
      _ -> :ok
    end
  end

  defp handle_action("monitor_performance", %{"params" => params}) do
    agent_id = params["agent_id"]
    duration = params["duration_ms"] || 60_000
    _ = Lang.Agent.Monitor.monitor_performance(agent_id, duration)
    :ok
  end

  defp parse_float(v) when is_number(v), do: v * 1.0

  defp parse_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      _ -> nil
    end
  end

  defp parse_float(_), do: nil

  defp handle_action(other, _args) do
    Logger.warning("Unknown agent task action", action: other)
    :ok
  end

  # --- Validation ---
  defp validate_args(action, %{"params" => params}) when is_map(params) do
    case action do
      a when a in ["anomaly_score", "audit_trail", "track_usage", "behavior_baseline"] ->
        require_keys(params, ["agent_id"])

      "trust_level" ->
        with :ok <- require_keys(params, ["agent_id", "threshold"]) do
          case params["threshold"] do
            t when is_number(t) and t >= 0 and t <= 1 ->
              :ok

            t when is_binary(t) ->
              case Float.parse(t) do
                {v, _} when v >= 0 and v <= 1 -> :ok
                _ -> {:error, {:invalid_threshold, t}}
              end

            other ->
              {:error, {:invalid_threshold, other}}
          end
        end

      "limit_resources" ->
        with :ok <- require_keys(params, ["agent_id", "resource_limits"]) do
          if is_map(params["resource_limits"]) do
            :ok
          else
            {:error, :resource_limits_must_be_map}
          end
        end

      "monitor_performance" ->
        with :ok <- require_keys(params, ["agent_id"]) do
          case {params["duration_ms"], params["window"]} do
            {d, _} when is_integer(d) and d > 0 ->
              :ok

            {d, _} when is_binary(d) ->
              case Integer.parse(d) do
                {i, ""} when i > 0 -> :ok
                _ -> {:error, :invalid_duration}
              end

            {_, w} when is_binary(w) and w != "" ->
              :ok

            {_, w} when is_integer(w) and w > 0 ->
              :ok

            _ ->
              {:error, :require_duration_or_window}
          end
        end

      _ ->
        :ok
    end
  end

  defp validate_args(_action, _), do: :ok

  defp require_keys(map, keys) do
    missing = Enum.filter(keys, fn k -> is_nil(Map.get(map, k)) end)
    if missing == [], do: :ok, else: {:error, {:missing_keys, missing}}
  end

  defp telemetry_meta(action, args) do
    %{
      action: action,
      user_id: args["user_id"],
      session_id: args["session_id"],
      project_id: args["project_id"],
      request_id: args["request_id"]
    }
  end

  defp redacted_args(args) do
    Map.update(args, "params", %{}, fn p -> Map.drop(p, ["token", "api_key"]) end)
  end
end
