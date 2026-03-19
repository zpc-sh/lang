defmodule Lang.LSP.ThinkExplainIntentStreamTest do
  use Lang.DataCase, async: false

  @topic "mcp_stream:session:test-sess"

  test "mcp streaming path returns stream_id and emits chunks" do
    # Subscribe for potential chunk events
    Phoenix.PubSub.subscribe(Lang.PubSub, @topic)

    # Mock StreamBridge to return a stream id without real setup
    with_mock(Lang.MCP.StreamBridge, [],
      create_stream: fn _conn_id, _user_id, _session_id, _opts ->
        {:ok, "stream-mcp-1"}
      end
    ) do
      # Mock provider router to return content with a summary field
      with_mock(Lang.Providers.Router, [],
        route_request: fn _method, _params, _opts ->
          {:ok, %{"summary" => String.duplicate("chunk-", 10)}}
        end
      ) do
        params = %{
          "client_id" => "cid-1",
          "content" => "def hello, do: :world",
          "mode" => "realtime",
          "stream_via" => "mcp",
          "mcp_connection_id" => "conn-1",
          "session_id" => "test-sess"
        }

        assert {:ok, %{stream_id: "stream-mcp-1", status: "streaming"}} =
                 Lang.Think.ExplainIntent.handle(params, %{})

        # Best-effort: receive at least one chunk or completion
        assert_receive {:mcp_stream_chunk, "stream-mcp-1", %{index: _i, chunk: _c}}, 500
      end
    end
  end
end

