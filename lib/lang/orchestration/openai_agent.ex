defmodule Lang.Orchestration.OpenAIAgent do
  @moduledoc """
  Lightweight OpenAI agent subscriber.

  Listens for tasks on `agent:tasks:openai` and routes them through the
  provider router, prioritizing generation/explanation methods.
  """

  use GenServer
  require Logger
  alias Phoenix.PubSub

  @tasks_topic "agent:tasks:openai"
  @agent_topic "agent:openai"
  @response_topic "orchestration:responses"

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    safe_subscribe(@tasks_topic)
    safe_subscribe(@agent_topic)
    {:ok, %{subs: [@tasks_topic, @agent_topic]}}
  end

  @impl true
  def handle_info({:task_assignment, message}, state) do
    message_id = Map.get(message, :message_id) || Map.get(message, "message_id")
    task = Map.get(message, :task) || Map.get(message, "task") || %{}
    type = Map.get(task, :type) || Map.get(task, "type")
    input = Map.get(task, :input_data) || Map.get(task, "input_data") || %{}
    context = Map.get(task, :context) || Map.get(task, "context") || %{}

    Logger.info("OpenAIAgent received task", type: inspect(type), id: message_id)

    method = select_method(type)
    params = build_params(method, input, context)

    result = Lang.Providers.Router.route_request(method, params, provider: :openai)

    PubSub.broadcast(Lang.PubSub, @response_topic, {:agent_response, message_id, tag_result(result, context)})

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp safe_subscribe(topic) do
    try do
      PubSub.subscribe(Lang.PubSub, topic)
    rescue
      _ -> :ok
    end
  end

  defp select_method(type) do
    case type do
      t when t in [:generation, "generation"] -> "lang.generate.from_spec"
      t when t in [:refactor, "refactor"] -> "lang.generate.optimize"
      _ -> "lang.think.explain_how"
    end
  end

  defp build_params(_method, input, context) do
    language = Map.get(context, :domain) || Map.get(context, "domain") || "text"
    code = Map.get(input, :code) || Map.get(input, "code")
    spec = Map.get(input, :specification) || Map.get(input, "specification")
    text = Map.get(input, :text) || Map.get(input, "text")

    cond do
      is_binary(spec) -> %{language: language, specification: spec}
      is_binary(code) -> %{language: language, code: code}
      is_binary(text) -> %{language: language, content: text}
      true -> %{language: language, content: inspect(input)}
    end
  end

  defp tag_result({:ok, res}, ctx), do: %{status: :ok, result: res, ctx: filter_ctx(ctx)}
  defp tag_result({:error, reason}, ctx), do: %{status: :error, error: inspect(reason), ctx: filter_ctx(ctx)}

  defp filter_ctx(ctx) do
    %{
      session_id: Map.get(ctx, :session_id) || Map.get(ctx, "session_id"),
      workspace_id: Map.get(ctx, :workspace_id) || Map.get(ctx, "workspace_id")
    }
  end
end

