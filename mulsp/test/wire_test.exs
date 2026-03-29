defmodule Mulsp.Transport.WireTest do
  use ExUnit.Case, async: true

  alias Mulsp.Transport.Wire

  describe "encode/decode" do
    test "text encode produces Content-Length header" do
      encoded = Wire.encode("hello world")
      assert encoded =~ "Content-Length: 11"
      assert encoded =~ "hello world"
    end

    test "text roundtrip" do
      original = "test message"
      encoded = Wire.encode(original)
      assert {:ok, ^original, <<>>} = Wire.decode(encoded)
    end

    test "term encode uses ETF content type" do
      encoded = Wire.encode(%{foo: "bar"})
      assert encoded =~ "Content-Type: application/erlang-etf"
    end

    test "incomplete message" do
      partial = "Content-Length: 100\r\n\r\nshort"
      assert {:incomplete, ^partial} = Wire.decode(partial)
    end

    test "missing headers" do
      assert {:incomplete, "garbage"} = Wire.decode("garbage")
    end
  end

  describe "parse_content_length" do
    test "parses valid header" do
      assert {:ok, 42} = Wire.parse_content_length("Content-Length: 42")
    end

    test "multiple headers" do
      headers = "Content-Type: text/plain\r\nContent-Length: 99"
      assert {:ok, 99} = Wire.parse_content_length(headers)
    end

    test "missing content-length" do
      assert :error = Wire.parse_content_length("Content-Type: text/plain")
    end
  end
end
