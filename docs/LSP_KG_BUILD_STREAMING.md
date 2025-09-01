# LSP Knowledge Graph Streaming (Ash PubSub)

This shows how to consume `lang.graph.build` streaming progress published via Ash PubSub.

When you call `lang.graph.build` with `{"stream": true}`, the server returns a `stream_id` and a PubSub topic. Progress events are published to Ash PubSub under:

- Topic: `lsp:kg_build:<stream_id>`
- Payload (transformed):
  - `stream_id`, `phase` (`:start | :extract | :build | :done | :error`),
  - `index`, `total`, `progress` (0.0–1.0), `complete` (bool),
  - `payload` (map with details or errors)

## Example: Start a streaming build

```bash
mix lsp.call lang.graph.build --json '{
  "stream": true,
  "documents": [
    {"format":"jsonld","content":"{\"@context\":\"https://schema.org/\",\"@type\":\"Person\",\"name\":\"Ada\"}"}
  ]
}'
# => {"result":{"stream_id":"kg_abcd1234...","topic":"lsp:kg_build:kg_abcd1234..."}}
```

## LiveView subscriber (example)

```elixir
defmodule LangWeb.KGBuildLive do
  use LangWeb, :live_view

  def mount(%{"stream_id" => stream_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(LangWeb.Endpoint, "lsp:kg_build:" <> stream_id)
    end

    {:ok,
     socket
     |> assign(:stream_id, stream_id)
     |> assign(:events, [])
     |> assign(:progress, 0.0)
     |> assign(:done, false)}
  end

  def handle_info(%{stream_id: id, phase: phase, progress: prog, complete: complete} = evt, socket) do
    socket =
      socket
      |> assign(:progress, prog || socket.assigns.progress)
      |> assign(:done, !!complete)
      |> update(:events, fn items -> [Map.put(evt, :at, DateTime.utc_now()) | Enum.take(items, 99)] end)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="max-w-3xl mx-auto space-y-4">
        <h1 class="text-xl font-semibold">KG Build Stream {@stream_id}</h1>
        <div class="w-full bg-gray-800 rounded h-3 overflow-hidden">
          <div class="bg-blue-500 h-3" style={"width: #{Float.round(@progress*100,1)}%"}></div>
        </div>
        <div :if={@done} class="text-green-400 text-sm">Build complete</div>
        <pre class="bg-gray-900 p-3 rounded text-xs overflow-auto h-64">
        <%= for evt <- @events do %>
          <%= inspect(evt) %>\n
        <% end %>
        </pre>
      </div>
    </Layouts.app>
    """
  end
end
```

Notes
- The events are emitted by an Ash resource (`Lang.LSP.Events.GraphBuildEvent`) with `Ash.Notifier.PubSub` and `module(LangWeb.Endpoint)`. Subscribe using `Phoenix.PubSub.subscribe(LangWeb.Endpoint, topic)`.
- Keep handlers lightweight—do not broadcast directly from the LSP handler. Always go through Ash resources/actions for events.
- For long builds, you can paginate or prune `@events` to avoid memory growth.
