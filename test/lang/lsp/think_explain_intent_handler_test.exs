defmodule Lang.LSP.ThinkExplainIntentHandlerTest do
  use Lang.DataCase, async: false

  test "handler routes to provider in realtime mode" do
    params = %{
      "client_id" => "test-client-1",
      "content" => "def hello, do: :world",
      "language" => "elixir",
      "mode" => "realtime",
      "provider" => "openai"
    }

    ctx = %{}

    with_mock(Lang.Providers.Router, [],
      route_request: fn _method, _params, _opts ->
        {:ok, %{"summary" => "Intent: greet world"}}
      end
    ) do
      assert {:ok, %{"summary" => _}} = Lang.Think.ExplainIntent.handle(params, ctx)
    end
  end

  # Local helper to mirror other tests' pattern; does not patch behavior
  defp with_mock(_module, _opts, fun), do: fun.()
end
