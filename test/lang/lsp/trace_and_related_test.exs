defmodule Lang.LSP.TraceAndRelatedTest do
  use ExUnit.Case, async: true

  test "trace_path returns invalid params when from/to missing" do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 7,
      "method" => "lang.spatial.trace_path",
      "params" => %{"project_id" => "proj-xyz"}
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"error" => %{"code" => -32602}} = resp
  end

  test "find_related returns invalid params when file missing" do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 8,
      "method" => "lang.spatial.find_related",
      "params" => %{"project_id" => "proj-xyz"}
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"error" => %{"code" => -32602}} = resp
  end
end
