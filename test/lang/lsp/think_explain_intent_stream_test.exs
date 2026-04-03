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

        assert_receive {:mcp_stream_chunk, "stream-mcp-1",
                        %{
                          index: _i,
                          chunk: _c,
                          trait_update: %{coherence: coherence, entropy: entropy},
                          audit_summary: chunk_summary
                        }}, 500

        assert is_float(coherence)
        assert is_float(entropy)
        assert String.starts_with?(chunk_summary, "chunk=")

        assert_receive {:mcp_stream_complete, "stream-mcp-1",
                        %{
                          "trait_aggregate" => %{
                            chunk_count: chunk_count,
                            avg_coherence: avg_coherence,
                            avg_entropy: avg_entropy,
                            overall_entropy: overall_entropy
                          },
                          "audit_summary" => turn_summary
                        }}, 500

        assert chunk_count >= 1
        assert is_float(avg_coherence)
        assert is_float(avg_entropy)
        assert is_float(overall_entropy)
        assert String.starts_with?(turn_summary, "turn_final")
      end
    end
  end
end
