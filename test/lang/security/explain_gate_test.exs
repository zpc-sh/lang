defmodule Lang.Security.ExplainGateTest do
  use ExUnit.Case, async: true

  test "evaluate_connect returns default allow verdict" do
    user = %{id: "u1"}
    org = %{id: "o1"}
    attrs = %{proto: "ws", url: "wss://example.org/socket"}

    assert {:ok, %{verdict: :allow, score: score, rationale: r}} =
             Lang.Security.ExplainGate.evaluate_connect(user, org, attrs)

    assert is_number(score) and score > 0
    assert is_binary(r) and r != ""
  end
end

