defmodule LangWeb.LSPHarnessLive do
  use LangWeb, :live_view
  alias Lang.LSP.Harness

  @topic "lsp:harness"

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Lang.PubSub, @topic)

    {:ok,
     socket
     |> assign(:page_title, "LSP Harness")
     |> assign(:running, false)
     |> assign(:clients, 4)
     |> assign(:iterations, 3)
     |> assign(:scenario, "read")
      |> assign(:stress, false)
      |> assign(:events, [])}
  end

  def handle_event("run", %{"clients" => c, "iterations" => it, "scenario" => sc, "stress" => stress}, socket) do
    clients = parse_int(c, 4)
    iterations = parse_int(it, 3)
    scenario = parse_scenario(sc)
    stress? = match?("true", to_string(stress))

    host = (System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
    port = String.to_integer(System.get_env("LSP_PORT") || "4001")

    send(self(), {:run_harness, %{host: host, port: port, clients: clients, iterations: iterations, scenario: scenario, stress_rate_limit: stress?}})

    {:noreply, assign(socket, :running, true) |> assign(:events, []) |> assign(:counters, %{})}
  end

  def handle_info({:run_harness, opts}, socket) do
    Task.Supervisor.start_child(Lang.LSP.TaskSupervisor, fn ->
      :ok = Application.ensure_all_started(:lang)
      summary = Harness.run(Keyword.merge(opts, emit: &emit/1))
      Phoenix.PubSub.broadcast(Lang.PubSub, @topic, {:harness_summary, summary})
    end)

    {:noreply, socket}
  end

  def handle_info({:harness_event, ev}, socket) do
    {:noreply,
     socket
     |> update(:events, fn evs -> [ev | evs] |> Enum.take(200) end)
     |> update(:counters, &accumulate(&1, ev))}
  end

  def handle_info({:harness_summary, %{ok: ok, error: error}}, socket) do
    {:noreply,
     socket
     |> assign(:running, false)
     |> update(:events, fn evs -> [%{event: "summary", ok: ok, error: error} | evs] end)}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-6">
      <h1 class="text-xl font-semibold mb-4">LSP Harness</h1>

      <.form for={%{}} id="harness-form" phx-submit="run" class="space-y-2">
        <div class="flex gap-2">
          <.input type="number" name="clients" value={@clients} min="1" class="w-32" label="Clients" />
          <.input type="number" name="iterations" value={@iterations} min="1" class="w-32" label="Iterations" />
          <select name="scenario" class="border rounded px-2 py-1">
            <option value="read" selected={@scenario == "read"}>read</option>
            <option value="write" selected={@scenario == "write"}>write</option>
            <option value="conflict" selected={@scenario == "conflict"}>conflict</option>
            <option value="mixed" selected={@scenario == "mixed"}>mixed</option>
            <option value="format_rename" selected={@scenario == "format_rename"}>format_rename</option>
          </select>
          <label class="flex items-center gap-2 text-sm">
            <input type="checkbox" name="stress" value="true" checked={@stress} />
            Rate-limit stress
          </label>
          <button type="submit" class="px-3 py-1 rounded bg-blue-600 text-white" disabled={@running}>
            <%= if @running, do: "Running…", else: "Run" %>
          </button>
        </div>
      </.form>

      <div id="events" class="mt-4 text-xs font-mono bg-slate-900 text-slate-100 p-3 rounded h-80 overflow-auto" phx-update="append">
        <div :for={ev <- Enum.reverse(@events)} id={event_id(ev)}>
          <%= Jason.encode!(ev) %>
        </div>
      </div>

      <div class="mt-4">
        <h2 class="text-sm font-semibold mb-2">Per-client counters</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-2 text-xs">
          <div :for={{cid, c} <- (@counters || %{})} class="border rounded p-2">
            <div class="font-mono text-slate-600">client_id: <%= cid %></div>
            <div class="mt-1">completion: <%= c[:completion] || 0 %>, hover: <%= c[:hover] || 0 %>, rename: <%= c[:rename] || 0 %>, formatting: <%= c[:formatting] || 0 %>, rate_limited: <%= c[:rate_limited] || 0 %>, error: <%= c[:error] || 0 %></div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp event_id(%{event: e, client_id: cid, iteration: it}), do: "#{e}-#{cid}-#{it}-#{System.unique_integer([:positive])}"
  defp event_id(%{event: e}), do: "#{e}-#{System.unique_integer([:positive])}"

  defp emit(map) when is_map(map) do
    Phoenix.PubSub.broadcast(Lang.PubSub, @topic, {:harness_event, map})
    :ok
  end

  defp parse_int(val, default) do
    case Integer.parse(to_string(val)) do
      {i, _} when i > 0 -> i
      _ -> default
    end
  end

  defp parse_scenario(sc) when is_binary(sc) do
    case String.downcase(sc) do
      "read" -> :read
      "write" -> :write
      "conflict" -> :conflict
      "mixed" -> :mixed
      "format_rename" -> :format_rename
      _ -> :read
    end
  end

  defp accumulate(counters, %{client_id: cid, event: ev}) do
    key = String.to_atom(ev)
    update_in(counters, [cid, key], fn
      nil -> 1
      n -> n + 1
    end)
  end
  defp accumulate(counters, %{client_id: cid, method: _m} = ev) do
    # treat generic with :rate_limited or :error from harness
    tag = (ev[:event] || "error") |> String.to_atom()
    update_in(counters, [cid, tag], fn
      nil -> 1
      n -> n + 1
    end)
  end
end
