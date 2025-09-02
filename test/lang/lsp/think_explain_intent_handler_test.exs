defmodule Lang.LSP.ThinkExplainIntentHandlerTest do
  use Lang.DataCase, async: false

  alias Lang.Think.Request

  test "handler enqueues request when not realtime" do
    params = %{
      "client_id" => "test-client-1",
      "content" => "def hello, do: :world",
      "language" => "elixir"
    }

    ctx = %{}

    assert {:ok, %{request_id: id, status: "queued"}} = Lang.Think.ExplainIntent.handle(params, ctx)

    {:ok, req} = Request.by_id(id)
    assert req.kind == :explain_intent
    assert req.status in [:pending, :running]
    assert get_in(req.input, ["content"]) || get_in(req.input, [:content])
  end
end

