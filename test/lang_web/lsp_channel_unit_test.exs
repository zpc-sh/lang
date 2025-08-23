defmodule LangWeb.LspChannelUnitTest do
  use ExUnit.Case, async: true

  alias LangWeb.LspChannel

  test "handle_in json rpc.initialize replies with capabilities" do
    socket = %Phoenix.Socket{assigns: %{rpc_ctx: %{api_key_id: "unit"}}}
    payload = %{"jsonrpc" => "2.0", "id" => "1", "method" => "rpc.initialize", "params" => %{"client" => %{"name" => "test"}}}

    {:reply, {:ok, reply}, _sock} = LspChannel.handle_in("json", payload, socket)
    assert Map.get(reply, "@context")
    assert get_in(reply, ["result", "capabilities", "service"]) == "lang"
  end

  test "handle_in json lang.fs.preview replies ok" do
    path = Path.join(System.tmp_dir!(), "lsp_channel_preview.txt")
    File.write!(path, "one\n")
    socket = %Phoenix.Socket{assigns: %{rpc_ctx: %{api_key_id: "unit"}}}
    payload = %{"jsonrpc" => "2.0", "id" => "2", "method" => "lang.fs.preview", "params" => %{"path" => path, "max_lines" => 1}}

    {:reply, {:ok, reply}, _sock} = LspChannel.handle_in("json", payload, socket)
    assert Map.get(reply, "@context")
    assert get_in(reply, ["result", "path"]) == path
  end
end

