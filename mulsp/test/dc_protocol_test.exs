defmodule Mulsp.DC.ProtocolTest do
  use ExUnit.Case, async: true

  alias Mulsp.DC.Protocol

  describe "encode/decode roundtrip" do
    test "ping roundtrips" do
      msg = Protocol.ping()
      encoded = Protocol.encode(msg)
      assert {:ok, {:ping, %{}}, <<>>} = Protocol.decode(encoded)
    end

    test "pong roundtrips" do
      msg = Protocol.pong()
      encoded = Protocol.encode(msg)
      assert {:ok, {:pong, %{}}, <<>>} = Protocol.decode(encoded)
    end

    test "bye roundtrips" do
      msg = Protocol.bye()
      encoded = Protocol.encode(msg)
      assert {:ok, {:bye, %{}}, <<>>} = Protocol.decode(encoded)
    end

    test "bloom_offer roundtrips" do
      sketch = <<1, 0, 1, 1, 0, 0, 1, 0>>
      msg = Protocol.bloom_offer(sketch, 42)
      encoded = Protocol.encode(msg)
      assert {:ok, {:bloom_offer, %{sketch: ^sketch, tokens: 42}}, <<>>} = Protocol.decode(encoded)
    end

    test "bloom_accept roundtrips" do
      msg = Protocol.bloom_accept()
      encoded = Protocol.encode(msg)
      assert {:ok, {:bloom_accept, %{}}, <<>>} = Protocol.decode(encoded)
    end

    test "bloom_reject roundtrips" do
      msg = Protocol.bloom_reject()
      encoded = Protocol.encode(msg)
      assert {:ok, {:bloom_reject, %{}}, <<>>} = Protocol.decode(encoded)
    end

    test "tree_begin roundtrips" do
      hash = :crypto.strong_rand_bytes(32)
      msg = Protocol.tree_begin(hash, 100)
      encoded = Protocol.encode(msg)
      assert {:ok, {:tree_begin, %{hash: ^hash, nodes: 100}}, <<>>} = Protocol.decode(encoded)
    end

    test "tree_chunk roundtrips" do
      nodes = [%{id: "abc", children: []}, %{id: "def", children: ["abc"]}]
      msg = Protocol.tree_chunk(3, nodes)
      encoded = Protocol.encode(msg)
      assert {:ok, {:tree_chunk, %{index: 3, nodes: ^nodes}}, <<>>} = Protocol.decode(encoded)
    end

    test "diff_payload roundtrips" do
      msg = Protocol.diff_payload(["a", "b"], ["c"], ["d"], 10)
      encoded = Protocol.encode(msg)

      assert {:ok,
              {:diff_payload,
               %{added: ["a", "b"], removed: ["c"], changed: ["d"], unchanged: 10}},
              <<>>} = Protocol.decode(encoded)
    end

    test "incomplete message returns :incomplete" do
      msg = Protocol.ping()
      encoded = Protocol.encode(msg)
      # Chop off last byte
      partial = binary_part(encoded, 0, byte_size(encoded) - 1)
      assert {:incomplete, ^partial} = Protocol.decode(partial)
    end

    test "concatenated messages decode one at a time" do
      msg1 = Protocol.ping()
      msg2 = Protocol.pong()
      combined = Protocol.encode(msg1) <> Protocol.encode(msg2)

      assert {:ok, {:ping, %{}}, rest} = Protocol.decode(combined)
      assert {:ok, {:pong, %{}}, <<>>} = Protocol.decode(rest)
    end
  end
end
