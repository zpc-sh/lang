defmodule LangWeb.ProxySessionLive do
  use LangWeb, :live_view

  alias Lang.Proxy.{SessionValidator, SessionTransformer, Pipeline, Envelope}

  @sample ~s/{
  "@type": "Session",
  "protocol": "ssh",
  "host": "127.0.0.1",
  "user": "lang",
  "cmd": "systemctl --user start engine"
}/

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:session_text, @sample)
     |> assign(:route, nil)
     |> assign(:pipeline_id, nil)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("preview", %{"session_text" => text}, socket) do
    with {:ok, session} <- Jason.decode(text),
         :ok <- SessionValidator.validate(session),
         {:ok, route} <- SessionTransformer.to_route(session, socket.assigns) do
      {:noreply, assign(socket, session_text: text, route: route, error: nil)}
    else
      {:error, reason} -> {:noreply, assign(socket, error: inspect(reason))}
      _ -> {:noreply, assign(socket, error: "Invalid session JSON or validation failed")}
    end
  end

  @impl true
  def handle_event("run", params, socket) do
    text = Map.get(params, "session_text", socket.assigns.session_text)
    with {:ok, session} <- Jason.decode(text),
         :ok <- SessionValidator.validate(session),
         {:ok, route} <- SessionTransformer.to_route(session, socket.assigns) do
      pipeline_id = gen_id()
      env = %Envelope{v: 1, service: :proxy, method: "pipeline.run", params: %{"route" => route, "pipeline_id" => pipeline_id}, opts: %{}, meta: socket.assigns, stream?: false}

      # run asynchronously so user can view streaming immediately
      Task.start(fn -> Pipeline.run(env, socket.assigns) end)

      {:noreply,
       socket
        |> assign(:route, route)
        |> assign(:pipeline_id, pipeline_id)
        |> assign(:error, nil)
       |> push_navigate(to: "/proxy/pipeline/" <> pipeline_id)}
    else
      {:error, reason} -> {:noreply, assign(socket, error: inspect(reason))}
      _ -> {:noreply, assign(socket, error: "Invalid session JSON or validation failed")}
    end
  end

  defp gen_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end
end
