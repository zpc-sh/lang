defmodule LangWeb.JSONLDRunnerLive do
  use LangWeb, :live_view

  @examples [
    {"Proxy SSH", ~S|{"lds:action":"proxy.connect","lds:proto":"ssh","lds:host":"example.com","lds:fingerprint":"sha256:..."}|},
    {"Emit Diagnostics", ~S|{"lds:action":"lsp.emit_diagnostics","uri":"file:///main.ex","diagnostics":{"items":[]}}|},
    {"Emit Completions", ~S|{"lds:action":"lsp.emit_completions","uri":"file:///main.ex","position":{"line":1,"col":1},"completions":{"items":[]}}|},
    {"Scan FS", ~S|{"lds:action":"analysis.scan_fs","path":"."}|}
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "JSON‑LD Runner")
      |> assign(:input, elem(hd(@examples), 1))
      |> assign(:parsed, nil)
      |> assign(:result, nil)
      |> assign(:error, nil)
      |> assign(:examples, @examples)
      |> assign(:registered, Lang.DevKit.JSONLDActions.allowed())
      |> assign(:subscribed_topics, MapSet.new())
      |> stream_configure(:events, dom_id: &event_dom_id/1)
      |> stream(:events, [])

    if connected?(socket) do
      Enum.each(default_topics(), &safe_subscribe/1)
      socket = assign(socket, :subscribed_topics, MapSet.new(default_topics()))
      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    input = params["input"]
    if is_binary(input) and String.trim(input) != "" do
      case decode(input) do
        {:ok, map} ->
          {:noreply, assign(socket, input: input, parsed: map, result: nil, error: nil)}
        {:error, reason} ->
          {:noreply, assign(socket, input: input, parsed: nil, result: nil, error: inspect(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("load_example", %{"value" => value}, socket) do
    {:noreply, assign(socket, input: value, parsed: nil, result: nil, error: nil)}
  end

  def handle_event("validate", %{"input" => input}, socket) do
    case decode(input) do
      {:ok, map} -> {:noreply, assign(socket, parsed: map, error: nil)}
      {:error, reason} -> {:noreply, assign(socket, error: inspect(reason), parsed: nil)}
    end
  end

  def handle_event("run", %{"input" => input}, socket) do
    with {:ok, map} <- decode(input),
         {:ok, result} <- Lang.Dev.JSONLDRunner.run(map) do
      {:noreply, assign(socket, parsed: map, result: result, error: nil)}
    else
      {:error, reason} -> {:noreply, assign(socket, error: inspect(reason))}
    end
  end

  def handle_event("copy_example", %{"text" => text}, socket) do
    {:noreply, push_event(socket, "copy-to-clipboard", %{text: text})}
  end

  def handle_event("register_action", %{"reg" => %{"name" => name, "type" => type, "topic" => topic}}, socket) do
    action = to_action_atom(name)
    fun =
      case type do
        "echo" -> fn payload -> {:ok, %{action: action, echo: payload}} end
        "broadcast" -> fn payload ->
          topic = String.trim(to_string(topic || "dev:events"))
          _ = try do Phoenix.PubSub.broadcast(Lang.PubSub, topic, payload) rescue _ -> :ok end
          {:ok, %{action: action, broadcasted_to: topic}}
        end
        _ -> fn _ -> {:error, :unsupported_handler} end
      end

    :ok = Lang.DevKit.JSONLDActions.register(action, fun)
    {:noreply, assign(socket, :registered, Lang.DevKit.JSONLDActions.allowed())}
  end

  def handle_event("subscribe_topic", %{"topic" => %{"name" => topic}}, socket) do
    topic = String.trim(to_string(topic))
    socket =
      if topic != "" do
        _ = safe_subscribe(topic)
        assign(socket, :subscribed_topics, MapSet.put(socket.assigns.subscribed_topics, topic))
      else
        socket
      end

    {:noreply, socket}
  end

  defp decode(str) when is_binary(str) do
    try do
      {:ok, Jason.decode!(str)}
    rescue
      _ -> {:error, :invalid_json}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dev_app flash={@flash}>
      <div class="p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-semibold">JSON‑LD Runner</h1>
          <a href="/dev/auth/impersonate/dev@lang.test?name=Dev%20User&return_to=/dev/jsonld" class="px-2 py-1 text-xs rounded bg-zinc-800 text-white hover:bg-zinc-700">Impersonate dev@lang.test</a>
        </div>

        <div class="flex gap-4">
          <div class="w-1/2 space-y-2">
            <label class="text-sm text-zinc-600">Examples</label>
            <div class="flex flex-col gap-1">
              <div :for={{label, json} <- @examples} class="flex items-center gap-2">
                <button phx-click="load_example" phx-value-value={json} class="px-2 py-1 text-xs rounded border hover:bg-zinc-50">{label}</button>
                <button phx-click="copy_example" phx-value-text={json} class="px-2 py-1 text-[10px] rounded bg-zinc-800 text-white hover:bg-zinc-700">Copy</button>
              </div>
            </div>

            <label class="text-sm text-zinc-600">Input (JSON‑LD)</label>
            <textarea id="jsonld-input" name="input" phx-debounce="250" class="w-full h-64 border rounded p-2 font-mono text-xs" phx-change="validate">{@input}</textarea>
            <div class="flex gap-2">
              <button phx-click="validate" phx-value-input={@input} class="px-3 py-1 text-xs rounded bg-zinc-800 text-white">Validate</button>
              <button phx-click="run" phx-value-input={@input} class="px-3 py-1 text-xs rounded bg-green-700 text-white">Run</button>
            </div>
          </div>

          <div class="w-1/2 space-y-3">
            <div class="border rounded p-2">
              <div class="font-medium mb-1">Parsed</div>
              <pre class="text-xs overflow-auto">{inspect(@parsed, pretty: true)}</pre>
            </div>
            <div class="border rounded p-2">
              <div class="font-medium mb-1">Result</div>
              <pre class="text-xs overflow-auto">{inspect(@result, pretty: true)}</pre>
            </div>
            <div :if={@error} class="border rounded p-2 text-red-600 bg-red-50">
              <div class="font-medium mb-1">Error</div>
              <pre class="text-xs overflow-auto">{@error}</pre>
            </div>

            <div class="border rounded p-2 space-y-2">
              <div class="font-medium mb-1">Events</div>
              <.form id="subscribe-form" for={to_form(%{}, as: :topic)} phx-submit="subscribe_topic" class="flex items-end gap-2">
                <div class="flex-1">
                  <label class="text-xs text-zinc-600">Subscribe to topic</label>
                  <input type="text" name="topic[name]" placeholder="lsp:diagnostics:global" class="w-full border rounded px-2 py-1 text-xs" />
                </div>
                <button class="px-2 py-1 text-xs rounded bg-zinc-800 text-white">Subscribe</button>
              </.form>
              <div class="text-xs text-zinc-500">Subscribed: {Enum.join(Enum.sort(MapSet.to_list(@subscribed_topics)), ", ")}</div>
              <div id="events" phx-update="stream" class="text-xs font-mono space-y-1 max-h-60 overflow-auto">
                <div :for={{id, e} <- @streams.events} id={id} class="truncate">{format_event(e)}</div>
              </div>
            </div>

            <div class="border rounded p-2 space-y-2">
              <div class="font-medium mb-1">Register Custom Action (dev)</div>
              <.form id="register-action" for={to_form(%{}, as: :reg)} phx-submit="register_action" class="grid grid-cols-3 gap-2 items-end">
                <div>
                  <label class="text-xs text-zinc-600">Name</label>
                  <input type="text" name="reg[name]" placeholder="custom.action" class="w-full border rounded px-2 py-1 text-xs" />
                </div>
                <div>
                  <label class="text-xs text-zinc-600">Type</label>
                  <select name="reg[type]" class="w-full border rounded px-2 py-1 text-xs">
                    <option value="echo">echo</option>
                    <option value="broadcast">broadcast</option>
                  </select>
                </div>
                <div>
                  <label class="text-xs text-zinc-600">Topic (broadcast)</label>
                  <input type="text" name="reg[topic]" placeholder="dev:events" class="w-full border rounded px-2 py-1 text-xs" />
                </div>
                <div class="col-span-3">
                  <button class="px-2 py-1 text-xs rounded bg-zinc-800 text-white">Register</button>
                </div>
              </.form>
              <div class="text-xs text-zinc-500">Allowed actions now: {inspect(@registered)}</div>
            </div>
          </div>
        </div>

        <div class="text-xs text-zinc-500">Whitelisted actions: {inspect(Lang.DevKit.JSONLDActions.allowed())}</div>

        <div class="mt-4 border rounded p-3 bg-zinc-50">
          <div class="font-medium mb-2">Quick Guide: Custom Actions</div>
          <div class="text-xs space-y-2 text-zinc-700">
            <div>
              <div class="font-semibold">Echo action</div>
              <div>1) Register in the panel above with Name <code>custom.echo</code>, Type <code>echo</code>.</div>
              <div>2) Run this JSON‑LD:</div>
              <div class="flex items-center gap-2">
                <button phx-click="copy_example" phx-value-text='{"lds:action":"custom.echo","hello":"world"}' class="px-2 py-0.5 text-xs rounded bg-zinc-800 text-white">Copy</button>
                <pre phx-no-curly-interpolation class="flex-1 mt-1 p-2 bg-white border rounded">{"lds:action":"custom.echo","hello":"world"}</pre>
              </div>
            </div>
            <div>
              <div class="font-semibold">Broadcast action</div>
              <div>1) Register with Name <code>custom.broadcast</code>, Type <code>broadcast</code>, Topic <code>dev:events</code>.</div>
              <div>2) Subscribe to <code>dev:events</code> in Events panel.</div>
              <div>3) Run this JSON‑LD:</div>
              <div class="flex items-center gap-2">
                <button phx-click="copy_example" phx-value-text='{"lds:action":"custom.broadcast","msg":"hi from runner"}' class="px-2 py-0.5 text-xs rounded bg-zinc-800 text-white">Copy</button>
                <pre phx-no-curly-interpolation class="flex-1 mt-1 p-2 bg-white border rounded">{"lds:action":"custom.broadcast","msg":"hi from runner"}</pre>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.dev_app>
    """
  end

  # Info handlers: collect anything reasonable and print concise entries
  @impl true
  def handle_info(%{__struct__: _} = struct, socket), do: {:noreply, stream_insert(socket, :events, %{type: :struct, data: struct})}
  def handle_info(%{} = map, socket), do: {:noreply, stream_insert(socket, :events, %{type: :map, data: map})}
  def handle_info(msg, socket), do: {:noreply, stream_insert(socket, :events, %{type: :msg, data: msg})}

  # Helpers -------------------------------------------------------------------
  defp default_topics, do: ["lsp:diagnostics:global", "lsp:completions:global"]

  defp safe_subscribe(topic) do
    _ = try do Phoenix.PubSub.subscribe(LangWeb.Endpoint, topic) rescue _ -> :ok end
    _ = try do Phoenix.PubSub.subscribe(Lang.PubSub, topic) rescue _ -> :ok end
    :ok
  end

  defp event_dom_id(e), do: "evt-" <> (:erlang.phash2(e) |> Integer.to_string())

  defp format_event(%{type: t, data: d}) when t in [:struct, :map, :msg], do: inspect(d)

  defp to_action_atom(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.to_atom()
  end
end
