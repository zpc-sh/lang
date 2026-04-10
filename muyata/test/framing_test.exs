defmodule Muyata.Observer.FramingTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Muyata.Observer.Framing)
    start_supervised!(Muyata.Observer.Census)
    start_supervised!(Muyata.Substrate.Tree)
    start_supervised!(Muyata.Substrate.Bloom)
    :ok
  end

  describe "initial state" do
    test "starts with no dominant hypothesis" do
      status = Muyata.Observer.Framing.status()
      assert status.dominant == nil
      assert status.framed_count == 0
    end

    test "has seed hypotheses" do
      status = Muyata.Observer.Framing.status()
      assert length(status.hypotheses) > 0

      types = Enum.map(status.hypotheses, & &1.type)
      assert :length_prefixed in types
      assert :tag_length in types
      assert :delimiter in types
    end
  end

  describe "hypothesis testing" do
    test "delimiter hypothesis gains confidence with delimited data" do
      # Send data with clear \r\n delimiters
      for _ <- 1..10 do
        Muyata.Observer.Framing.ingest(:client, "HELLO WORLD\r\n")
      end

      :timer.sleep(50)
      status = Muyata.Observer.Framing.status()

      crlf =
        Enum.find(status.hypotheses, fn h ->
          h.type == :delimiter and h.params.sequence == "\r\n"
        end)

      assert crlf != nil
      assert crlf.hits > 0
    end

    test "tag+length hypothesis tested with binary data" do
      # Simulate PostgreSQL-style tag+length message: 'Q' + 4-byte length + payload
      # Length includes itself (4 bytes) so total payload = length - 4
      tag = "Q"
      payload = "SELECT 1"
      len = byte_size(payload) + 4
      message = tag <> <<len::32>> <> payload

      for _ <- 1..5 do
        Muyata.Observer.Framing.ingest(:client, message)
      end

      :timer.sleep(50)
      status = Muyata.Observer.Framing.status()

      tag_len =
        Enum.find(status.hypotheses, fn h ->
          h.type == :tag_length and h.params.tag_bytes == 1 and h.params.len_bytes == 4
        end)

      assert tag_len != nil
      assert tag_len.hits > 0
    end
  end
end
