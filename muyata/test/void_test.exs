defmodule Muyata.VoidTest do
  use ExUnit.Case, async: false

  setup do
    # Start just the Void GenServer for isolated testing
    start_supervised!(Muyata.Void)
    :ok
  end

  describe "initial state" do
    test "starts with zero knowledge" do
      void = Muyata.Void.state()
      assert void.epoch == 0
      assert void.patterns_seen == 0
      assert void.bytes_observed == 0
      assert void.connections_seen == 0
    end

    test "has a node_id" do
      void = Muyata.Void.state()
      assert String.starts_with?(void.node_id, "muyata-")
    end

    test "has default ports" do
      void = Muyata.Void.state()
      assert void.listen_port == 5432
      assert void.upstream_port == 5433
    end
  end

  describe "observation" do
    test "observe_bytes increments counter" do
      Muyata.Void.observe_bytes(100)
      Muyata.Void.observe_bytes(200)
      # Give GenServer time to process casts
      :timer.sleep(10)
      void = Muyata.Void.state()
      assert void.bytes_observed == 300
    end

    test "new_pattern increments counter" do
      Muyata.Void.new_pattern()
      Muyata.Void.new_pattern()
      :timer.sleep(10)
      void = Muyata.Void.state()
      assert void.patterns_seen == 2
    end

    test "new_connection increments counter" do
      Muyata.Void.new_connection()
      :timer.sleep(10)
      void = Muyata.Void.state()
      assert void.connections_seen == 1
    end
  end

  describe "epoch" do
    test "advance_epoch increments" do
      {:ok, 1} = Muyata.Void.advance_epoch()
      {:ok, 2} = Muyata.Void.advance_epoch()
      void = Muyata.Void.state()
      assert void.epoch == 2
    end
  end
end
