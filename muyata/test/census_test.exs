defmodule Muyata.Observer.CensusTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Muyata.Observer.Census)
    start_supervised!(Muyata.Void)
    start_supervised!(Muyata.Substrate.Tree)
    start_supervised!(Muyata.Substrate.Bloom)
    :ok
  end

  describe "classification" do
    test "starts with zero patterns" do
      assert Muyata.Observer.Census.count() == 0
      assert Muyata.Observer.Census.patterns() == []
    end

    test "classifies messages by first byte" do
      Muyata.Observer.Census.classify(:client, <<0x51, "SELECT 1">>)
      Muyata.Observer.Census.classify(:client, <<0x51, "SELECT 2">>)
      Muyata.Observer.Census.classify(:server, <<0x54, "RowDescription">>)

      :timer.sleep(50)

      assert Muyata.Observer.Census.count() == 2

      patterns = Muyata.Observer.Census.patterns()
      assert length(patterns) == 2

      q_pattern = Enum.find(patterns, &(&1.tag == "0x51"))
      assert q_pattern != nil
      assert q_pattern.count == 2
    end

    test "tracks direction" do
      Muyata.Observer.Census.classify(:client, <<0x42, "bind data">>)
      Muyata.Observer.Census.classify(:server, <<0x32, "bind complete">>)
      :timer.sleep(50)

      patterns = Muyata.Observer.Census.patterns()
      client_pattern = Enum.find(patterns, &(&1.tag == "0x42"))
      assert client_pattern.directions[:client] == 1
    end

    test "registers new patterns in void" do
      Muyata.Observer.Census.classify(:client, <<0xAA, "test">>)
      :timer.sleep(50)

      void = Muyata.Void.state()
      assert void.patterns_seen >= 1
    end

    test "adds to bloom filter" do
      Muyata.Observer.Census.classify(:client, <<0xBB, "data">>)
      :timer.sleep(50)

      assert Muyata.Substrate.Bloom.check("msg_type_BB")
    end
  end
end
