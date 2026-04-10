defmodule Muyata.ShapeTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Muyata.Void)
    start_supervised!(Muyata.Observer.Framing)
    start_supervised!(Muyata.Observer.Census)
    start_supervised!(Muyata.Observer.Heatmap)
    start_supervised!(Muyata.Substrate.Tree)
    start_supervised!(Muyata.Substrate.Bloom)
    :ok
  end

  describe "seal" do
    test "creates a shape from current state" do
      shape = Muyata.Shape.seal("test-shape")
      assert shape.name == "test-shape"
      assert shape.epoch == 0
      assert shape.coverage == 0.0
      assert shape.message_types == %{}
    end

    test "default name includes epoch" do
      shape = Muyata.Shape.seal()
      assert String.starts_with?(shape.name, "shape-")
    end
  end

  describe "merge" do
    test "merges two shapes" do
      a = %Muyata.Shape{
        name: "a",
        epoch: 3,
        coverage: 0.1,
        message_types: %{
          "0x51" => %{count: 10, avg_len: 100, directions: %{client: 10}}
        }
      }

      b = %Muyata.Shape{
        name: "b",
        epoch: 5,
        coverage: 0.2,
        message_types: %{
          "0x51" => %{count: 20, avg_len: 200, directions: %{client: 20}},
          "0x54" => %{count: 5, avg_len: 50, directions: %{server: 5}}
        }
      }

      merged = Muyata.Shape.merge(a, b)
      assert merged.epoch == 5
      assert map_size(merged.message_types) == 2
      assert merged.message_types["0x51"].count == 30
    end
  end

  describe "diff" do
    test "shows differences between shapes" do
      a = %Muyata.Shape{
        name: "a",
        coverage: 0.1,
        message_types: %{"0x51" => %{}, "0x50" => %{}}
      }

      b = %Muyata.Shape{
        name: "b",
        coverage: 0.3,
        message_types: %{"0x51" => %{}, "0x54" => %{}}
      }

      diff = Muyata.Shape.diff(a, b)
      assert "0x50" in diff.only_in_a
      assert "0x54" in diff.only_in_b
      assert diff.shared == 1
      assert diff.coverage_delta == 0.2
    end
  end

  describe "serialization" do
    test "roundtrips through ETF" do
      shape = Muyata.Shape.seal("roundtrip-test")
      etf = Muyata.Shape.to_etf(shape)
      restored = Muyata.Shape.from_etf(etf)

      assert restored.name == "roundtrip-test"
      assert restored.epoch == shape.epoch
    end
  end
end
