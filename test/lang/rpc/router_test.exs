defmodule Lang.RPC.RouterTest do
  use ExUnit.Case, async: true

  alias Lang.RPC.Router

  test "rpc.initialize returns capabilities with auth" do
    ctx = %{api_key_id: "test-key"}
    {:ok, %{capabilities: caps, client: client}} =
      Router.dispatch(ctx, "rpc.initialize", %{"client" => %{"name" => "test", "version" => "0.1"}})

    assert caps.service == "lang"
    assert is_binary(caps.version)
    assert "rpc.ping" in caps.methods
    assert "lang.fs.preview" in caps.methods
    assert caps.auth.api_key_id == "test-key"
    assert client["name"] == "test"
  end

  test "rpc.stream_example emits chunk and completion messages" do
    ctx = %{channel_pid: self()}
    {:ok, %{stream_id: sid}} = Router.dispatch(ctx, "rpc.stream_example", %{"request_id" => "t1"})
    assert sid == "t1"

    assert_receive {:rpc_stream, "t1", {:chunk, %{n: 1, message: "hello"}}}, 500
    assert_receive {:rpc_stream, "t1", {:chunk, %{n: 2, message: "hello"}}}, 500
    assert_receive {:rpc_stream, "t1", {:chunk, %{n: 3, message: "hello"}}}, 500
    assert_receive {:rpc_stream_completed, "t1"}, 500
  end

  test "lang.fs.preview returns lines" do
    path = Path.join(System.tmp_dir!(), "router_test_preview.txt")
    File.write!(path, "line1\nline2\nline3\n")

    {:ok, %{path: ^path, lines: lines, max_lines: 2}} =
      Router.dispatch(%{}, "lang.fs.preview", %{"path" => path, "max_lines" => 2})

    assert length(lines) == 2
    assert Enum.at(lines, 0) == "line1"
    assert Enum.at(lines, 1) == "line2"
  end
end

