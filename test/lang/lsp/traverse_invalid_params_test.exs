defmodule Lang.LSP.TraverseInvalidParamsTest do
  use ExUnit.Case, async: true

  test "negative depth returns invalid params error" do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 300,
      "method" => "lang.spatial.traverse",
      "params" => %{"project_id" => "proj-x", "file" => "a.ex", "depth" => -1}
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"error" => %{"code" => -32602, "message" => "invalid depth param"}} = resp
  end

  test "non-integer depth returns invalid params error" do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 301,
      "method" => "lang.spatial.traverse",
      "params" => %{"project_id" => "proj-x", "file" => "a.ex", "depth" => "abc"}
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"error" => %{"code" => -32602}} = resp
  end
end

