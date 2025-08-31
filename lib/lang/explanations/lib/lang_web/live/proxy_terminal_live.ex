defmodule LangWeb.ProxyTerminalLive do
  use LangWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    session_id = params["id"] || gen_id()

    # Defaults; can be overridden via query params
    proto = params["proto"] || "ssh"
    assigns = %{
      page_title: "Terminal Session",
      session_id: session_id,
      proto: proto,
      host: params["host"],
      port: params["port"],
      user: params["user"],
      fingerprint: params["fingerprint"],
      path: params["path"],
      url: params["url"],
      policy: params["policy"] || "attach"
    }

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dev_app flash={@flash}>
      <div class="p-4">
        <div class="flex items-center justify-between mb-2">
          <h1 class="text-xl font-semibold">Terminal Session</h1>
          <a href="/dev/auth/impersonate/dev@lang.test?name=Dev%20User&return_to=/dev/proxy/terminal"
             class="px-2 py-1 text-xs rounded bg-zinc-800 text-white hover:bg-zinc-700">Impersonate dev@lang.test</a>
        </div>
        <div class="mb-3 text-sm text-gray-600">Session ID: {@session_id}</div>

        <div id="mdld-session"
             phx-hook="MdldSession"
             data-terminal
             data-action="connect"
             data-connect={"/api/sessions/#{@session_id}/connect"}
             data-session-id={@session_id}
             data-proto={@proto}
             data-host={@host}
             data-port={@port}
             data-user={@user}
             data-fingerprint={@fingerprint}
             data-path={@path}
             data-url={@url}
             data-policy={@policy}
             data-cols="100"
             data-rows="28"
             class="border rounded bg-black text-green-400 p-2 h-[420px] flex flex-col">
          <div class="mb-2">
            <button type="button"
                    data-action="connect"
                    class="btn btn-primary px-3 py-1 text-sm">Connect</button>
          </div>
          <div class="flex-1 overflow-auto border rounded p-2 bg-black/80 text-green-400 text-xs" data-terminal></div>
        </div>
      </div>
    </Layouts.dev_app>
    """
  end

  defp gen_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end
end
