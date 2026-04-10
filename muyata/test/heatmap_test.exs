defmodule Muyata.Observer.HeatmapTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Muyata.Observer.Heatmap)
    :ok
  end

  describe "coverage" do
    test "starts at zero coverage" do
      assert Muyata.Observer.Heatmap.coverage() == 0.0
    end

    test "coverage increases with observations" do
      Muyata.Observer.Heatmap.observe(<<0x51, 0x00, 0x00, 0x0D>>)
      :timer.sleep(10)

      coverage = Muyata.Observer.Heatmap.coverage()
      assert coverage > 0.0
    end
  end

  describe "grid" do
    test "starts empty" do
      assert Muyata.Observer.Heatmap.grid() == %{}
    end

    test "records byte pairs" do
      Muyata.Observer.Heatmap.observe(<<0xAA, 0xBB, 0xCC>>)
      :timer.sleep(10)

      grid = Muyata.Observer.Heatmap.grid()
      assert Map.get(grid, {0xAA, 0xBB}) == 1
      assert Map.get(grid, {0xBB, 0xCC}) == 1
    end
  end

  describe "hot spots" do
    test "returns most frequent pairs" do
      for _ <- 1..10 do
        Muyata.Observer.Heatmap.observe(<<0x51, 0x00>>)
      end

      Muyata.Observer.Heatmap.observe(<<0xAA, 0xBB>>)
      :timer.sleep(20)

      spots = Muyata.Observer.Heatmap.hot_spots(1)
      assert length(spots) == 1
      [top | _] = spots
      assert top.byte1 == "0x51"
      assert top.count == 10
    end
  end

  describe "ascii rendering" do
    test "renders without crashing" do
      Muyata.Observer.Heatmap.observe(<<0x51, 0x00, 0x00, 0x0D>>)
      :timer.sleep(10)

      ascii = Muyata.Observer.Heatmap.render_ascii()
      assert is_binary(ascii)
      assert String.contains?(ascii, ".")
    end
  end
end
