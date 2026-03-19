defmodule Lang.Orchestration.QwenAgent do
  @moduledoc """
  Lightweight Qwen agent subscriber.

  - Subscribes to PubSub topics for Qwen-directed tasks
  - Routes tasks through existing provider router (with its own selection)
  - Publishes responses to orchestration response topic
  """

  use GenServer
  require Logger
  alias Phoenix.PubSub

  @tasks_topic "agent:tasks:qwen"
  @agent_topic "agent:qwen"
  @response_topic "orchestration:responses"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Best-effort subscriptions
    safe_subscribe(@tasks_topic)
    safe_subscribe(@agent_topic)
    {:ok, %{subs: [@tasks_topic, @agent_topic]}}
  end

  @impl true
  def handle_info({:task_assignment, message}, state) when is_map(message) do
    message_id = Map.get(message, :message_id) || Map.get(message, "message_id")
    task = Map.get(message, :task) || Map.get(message, "task") || %{}
    type = Map.get(task, :type) || Map.get(task, "type")
    input = Map.get(task, :input_data) || Map.get(task, "input_data") || %{}
    context = Map.get(task, :context) || Map.get(task, "context") || %{}

    Logger.info("QwenAgent received task", type: inspect(type), id: message_id)

    method = select_method(type)
    params = build_params(method, input, context)

    result = Lang.Providers.Router.route_request(method, params)

    PubSub.broadcast(Lang.PubSub, @response_topic, {:agent_response, message_id, format_result(result)})

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- helpers ---

  defp safe_subscribe(topic) do
    try do
      PubSub.subscribe(Lang.PubSub, topic)
    rescue
      _ -> :ok
    end
  end

  defp select_method(type) do
    case type do
      t when t in [:performance_analysis, "performance_analysis"] -> "lang.think.predict_performance"
      t when t in [:mathematical_optimization, "mathematical_optimization"] -> "lang.think.explain_how"
      _ -> "lang.think.explain_how"
    end
  end

  defp build_params(_method, input, context) do
    language = Map.get(context, :domain) || Map.get(context, "domain") || "text"
    code = Map.get(input, :code) || Map.get(input, "code")
    text = Map.get(input, :text) || Map.get(input, "text")

    cond do
      is_binary(code) -> %{language: language, code: code}
      is_binary(text) -> %{language: language, content: text}
      true -> %{language: language, content: inspect(input)}
    end
  end

  defp format_result({:ok, res}), do: %{status: :ok, result: res}
  defp format_result({:error, reason}), do: %{status: :error, error: inspect(reason)}
end

