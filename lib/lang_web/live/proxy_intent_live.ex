defmodule LangWeb.ProxyIntentLive do
  use LangWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:service, "lsp")
     |> assign(:method, "lsp.bootstrap_ssh")
     |> assign(:scopes, "ssh:bootstrap")
     |> assign(:ttl, 300)
     |> assign(:token, nil)
     |> assign(:exp, nil)}
  end

  @impl true
  def handle_event("issue", %{"service" => svc, "method" => meth, "scopes" => scopes, "ttl" => ttl_str}, socket) do
    ttl = parse_int(ttl_str, 300)
    exp = System.os_time(:second) + ttl
    org = socket.assigns[:current_org]
    user = socket.assigns[:current_user]
    claims = %{
      "org_id" => org && org.id,
      "user_id" => user && user.id,
      "service" => svc,
      "method" => meth,
      "scope" => parse_scopes(scopes),
      "exp" => exp,
      "nonce" => Base.encode64(:crypto.strong_rand_bytes(12))
    }

    case Lang.Proxy.Intent.sign(claims) do
      {:ok, tok} -> {:noreply, assign(socket, token: tok, exp: exp)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed to sign: #{inspect(reason)}")}
    end
  end

  defp parse_scopes(s) when is_binary(s) do
    s
    |> String.split([",", " "], trim: true)
    |> Enum.reject(&(&1 == ""))
  end
  defp parse_scopes(_), do: []

  defp parse_int(v, default) do
    case Integer.parse(to_string(v)) do
      {i, _} -> i
      _ -> default
    end
  end
end

