defmodule Lang.Timeline.Decisions do
  @moduledoc "Key architectural decision points"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.timeline.find_decisions"

  require Logger

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # Extract params and setup routing via Providers
    timeline_id = Map.get(params, "timeline_id") || Map.get(params, "timeline")

    if timeline_id do
      find(timeline_id, params, ctx)
    else
      {:error, -32602, "Missing required parameter: timeline_id"}
    end
  end

  def find(timeline_id, params, _ctx \\ %{}) do
    case Lang.Timeline.StateManager.get_timeline_history(timeline_id) do
      {:ok, history} ->
        # Use AI router to analyze the timeline history and extract key architectural decisions
        prompt = """
        Analyze the following code evolution timeline and identify key architectural decisions.

        Timeline ID: #{timeline_id}

        History:
        #{inspect(history, pretty: true, limit: :infinity)}

        Extract:
        1. Major structural changes
        2. Technology/dependency additions or removals
        3. Pattern shifts (e.g., MVC to CQRS)
        4. The rationale or inferred intent behind these decisions

        Format the response as a JSON array of decisions with 'id', 'timestamp', 'description', and 'impact'.
        """

        provider_opts = [
          provider: :anthropic, # Anthropic excels at architectural analysis and large contexts
          model: Map.get(params, "model", "claude-3-5-sonnet-latest"),
          temperature: Map.get(params, "temperature", 0.2)
        ]

        # We need to construct LSP-compatible params for the route_request
        route_params = Map.put(params, "prompt", prompt)

        case Lang.Providers.Router.route_request(@lsp_method, route_params, provider_opts) do
          {:ok, result} ->
            {:ok, %{timeline_id: timeline_id, decisions: result}}

          {:error, reason} ->
            Logger.error("Failed to find decisions via AI: #{inspect(reason)}")
            {:error, -32603, "Failed to analyze decisions", %{reason: inspect(reason)}}
        end

      {:error, reason} ->
        {:error, -32603, "Failed to fetch timeline history", %{reason: inspect(reason)}}
    end
  end
end
