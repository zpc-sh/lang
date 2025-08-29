defmodule Lang.LSP.CapabilitiesTest do
  use ExUnit.Case, async: true

  test "capabilities includes spatial methods" do
    msg = %{"jsonrpc" => "2.0", "id" => 1, "method" => "lang.capabilities"}
    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"result" => %{"implemented" => impl}} = resp
    assert "lang.spatial.trace_path" in impl
    assert "lang.spatial.find_related" in impl
  end

  test "not implemented methods return -32601" do
    msg = %{"jsonrpc" => "2.0", "id" => 2, "method" => "lang.generate.from_spec"}
    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"error" => %{"code" => -32601}} = resp
  end
end
