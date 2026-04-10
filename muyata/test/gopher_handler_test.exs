defmodule Muyata.Gopher.HandlerTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Muyata.Void)
    start_supervised!(Muyata.Observer.Tap)
    start_supervised!(Muyata.Observer.Framing)
    start_supervised!(Muyata.Observer.Census)
    start_supervised!(Muyata.Observer.Heatmap)
    start_supervised!(Muyata.Substrate.Tree)
    start_supervised!(Muyata.Substrate.Bloom)
    start_supervised!(Muyata.Substrate.Epoch)
    start_supervised!({Muyata.Mesh.Cluster, []})
    :ok
  end

  describe "handle/3" do
    test "root menu contains muyata identity" do
      response = Muyata.Gopher.Handler.handle("", "localhost", 7170)
      assert response =~ "muyata"
      assert response =~ ".\r\n"
    end

    test "root menu has navigation links" do
      response = Muyata.Gopher.Handler.handle("/", "localhost", 7170)
      assert response =~ "Void State"
      assert response =~ "Framing Hypotheses"
      assert response =~ "Message Patterns"
      assert response =~ "Coverage Heatmap"
      assert response =~ "Merkin Tree"
    end

    test "/void shows void state" do
      response = Muyata.Gopher.Handler.handle("/void", "localhost", 7170)
      assert response =~ "VOID STATE"
      assert response =~ "node_id:"
      assert response =~ "epoch: 0"
      assert response =~ "patterns_seen: 0"
    end

    test "/framing shows hypotheses" do
      response = Muyata.Gopher.Handler.handle("/framing", "localhost", 7170)
      assert response =~ "FRAMING HYPOTHESES"
      assert response =~ "dominant:"
    end

    test "/patterns shows message types" do
      response = Muyata.Gopher.Handler.handle("/patterns", "localhost", 7170)
      assert response =~ "MESSAGE PATTERNS"
    end

    test "/heatmap renders ASCII" do
      response = Muyata.Gopher.Handler.handle("/heatmap", "localhost", 7170)
      assert response =~ "COVERAGE HEATMAP"
    end

    test "/tree shows merkin tree" do
      response = Muyata.Gopher.Handler.handle("/tree", "localhost", 7170)
      assert response =~ "MERKIN TREE"
      assert response =~ "nodes:"
    end

    test "/bloom shows filter stats" do
      response = Muyata.Gopher.Handler.handle("/bloom", "localhost", 7170)
      assert response =~ "BLOOM FILTER"
      assert response =~ "bit_size:"
    end

    test "/mesh shows peer status" do
      response = Muyata.Gopher.Handler.handle("/mesh", "localhost", 7170)
      assert response =~ "MESH PEERS"
    end

    test "unknown selector returns error" do
      response = Muyata.Gopher.Handler.handle("/nonexistent", "localhost", 7170)
      assert response =~ "Not found"
    end
  end
end
