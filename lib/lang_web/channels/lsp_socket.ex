defmodule LangWeb.LspSocket do
  use Phoenix.Socket

  channel "lsp:*", LangWeb.LspChannel

  def connect(%{"api_key" => api_key} = _params, socket, connect_info) when is_binary(api_key) do
    do_connect(api_key, socket, connect_info)
  end

  def connect(_params, socket, connect_info) do
    # Test bypass: allow connecting without API key for integration tests
    if rpc_test_bypass?(connect_info) do
      ctx = %{
        api_key_id: "test",
        user: nil,
        organization: nil,
        scopes: ["read"],
        client_ip: peer_ip(connect_info[:peer_data])
      }

      {:ok, Phoenix.Socket.assign(socket, :rpc_ctx, ctx)}
    else
      api_key = header_api_key(connect_info[:x_headers]) || uri_api_key(connect_info[:uri])

      if is_binary(api_key) do
        do_connect(api_key, socket, connect_info)
      else
        :error
      end
    end
  end

  def id(_socket), do: nil

  defp do_connect(api_key, socket, connect_info) do
    ip = peer_ip(connect_info[:peer_data])

    case Lang.Accounts.ApiKey.authenticate(api_key) do
      {:ok, key} ->
        if Lang.Accounts.ApiKey.allowed_ip?(key, ip) do
          {:ok,
           Phoenix.Socket.assign(socket, :rpc_ctx, %{
             api_key_id: key.id,
             user: key.user,
             organization: key.organization,
             scopes: key.scopes || [],
             client_ip: ip
           })}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp header_api_key(nil), do: nil

  defp header_api_key(headers) when is_list(headers) do
    headers
    |> Enum.find_value(fn {k, v} ->
      if String.downcase(to_string(k)) in ["sec-lang-api-key", "authorization"] do
        case v do
          "Bearer " <> token -> token
          token -> token
        end
      else
        nil
      end
    end)
  end

  defp uri_api_key(nil), do: nil
  defp uri_api_key(%URI{query: nil}), do: nil

  defp uri_api_key(%URI{query: q}) do
    q
    |> URI.decode_query()
    |> Map.get("api_key")
  end

  defp peer_ip(nil), do: nil
  defp peer_ip(%{address: {a, b, c, d}}), do: :inet_parse.ntoa({a, b, c, d}) |> to_string()
  defp peer_ip(%{address: addr}), do: inspect(addr)

  defp rpc_test_bypass?(connect_info) do
    bypass_cfg = Application.get_env(:lang, :rpc_test_bypass, Mix.env() == :test)

    case connect_info[:uri] do
      %URI{query: q} when is_binary(q) ->
        params = URI.decode_query(q)
        bypass_param = params["test_bypass"] in ["true", "1", true]
        bypass_cfg and bypass_param

      _ ->
        false
    end
  end
end
