defmodule Lang.LSP.CapabilitiesPlannedTest do
  use ExUnit.Case, async: true

  test "planned includes key methods from lsp.md" do
    msg = %{"jsonrpc" => "2.0", "id" => 99, "method" => "lang.capabilities"}
    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"result" => %{"planned" => planned}} = resp
    assert is_list(planned)
    # Spot check a few planned items from docs
    assert "lang.generate.from_spec" in planned
    assert "lang.agent.spawn" in planned
    assert "lang.timeline.evolution" in planned
  end
end
