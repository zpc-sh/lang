defmodule Lang.LSP.TraverseTest do
  use ExUnit.Case, async: true

  test "traverse returns invalid params when file missing" do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 42,
      "method" => "lang.spatial.traverse",
      "params" => %{"project_id" => "proj-1", "depth" => 2}
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"error" => %{"code" => -32602}} = resp
  end
end
