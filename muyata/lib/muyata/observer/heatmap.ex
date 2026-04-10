defmodule Muyata.Observer.Heatmap do
  @moduledoc """
  Protocol coverage heatmap — Rice's theorem's honest answer.

  A 256x256 sparse grid mapping the observed protocol space:
  - X axis: first byte of message (tag/type byte)
  - Y axis: second byte (structure indicator)
  - Heat: observation frequency (log scale)

  The heatmap shows what we've seen and — more importantly — the
  shape of our ignorance. Hot clusters are well-understood message
  types. Cold regions are the unknown. Warm edges are partially
  emergent patterns that need more traffic.

  Claudes or humans can look at the heatmap, see the cold spots,
  and use probabilistic shaping to fill in the gaps.
  """
  use GenServer

  @grid_size 256

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Observe raw bytes (updates the byte-pair grid)."
  def observe(data) when is_binary(data) do
    GenServer.cast(__MODULE__, {:observe, data})
  end

  @doc "Get the sparse grid as a map of {x, y} => count."
  def grid do
    GenServer.call(__MODULE__, :grid)
  end

  @doc "Get top-N most frequently observed byte pairs."
  def hot_spots(n \\ 10) do
    GenServer.call(__MODULE__, {:hot_spots, n})
  end

  @doc "Coverage: fraction of the 256x256 space that has been observed."
  def coverage do
    GenServer.call(__MODULE__, :coverage)
  end

  @doc "Render as ASCII art (compact)."
  def render_ascii do
    GenServer.call(__MODULE__, :render_ascii)
  end

  @impl true
  def init(_opts) do
    {:ok, %{grid: %{}, total_observations: 0}}
  end

  @impl true
  def handle_cast({:observe, data}, state) do
    state = scan_byte_pairs(data, state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:grid, _from, state) do
    {:reply, state.grid, state}
  end

  def handle_call({:hot_spots, n}, _from, state) do
    spots =
      state.grid
      |> Enum.sort_by(fn {_k, v} -> v end, :desc)
      |> Enum.take(n)
      |> Enum.map(fn {{x, y}, count} ->
        %{byte1: hex(x), byte2: hex(y), count: count}
      end)

    {:reply, spots, state}
  end

  def handle_call(:coverage, _from, state) do
    cells_seen = map_size(state.grid)
    total_cells = @grid_size * @grid_size
    {:reply, Float.round(cells_seen / total_cells, 6), state}
  end

  def handle_call(:render_ascii, _from, state) do
    ascii = render_grid(state.grid)
    {:reply, ascii, state}
  end

  defp scan_byte_pairs(<<a::8, b::8, rest::binary>>, state) do
    grid = Map.update(state.grid, {a, b}, 1, &(&1 + 1))
    state = %{state | grid: grid, total_observations: state.total_observations + 1}
    scan_byte_pairs(<<b::8, rest::binary>>, state)
  end

  defp scan_byte_pairs(_too_short, state), do: state

  defp render_grid(grid) do
    # Render a 16x16 summary (grouping 16 byte values per cell)
    max_val = grid |> Map.values() |> Enum.max(fn -> 0 end)

    header = "    " <> Enum.map_join(0..15, " ", &hex_nibble/1) <> "\n"

    rows =
      Enum.map_join(0..15, "\n", fn row ->
        prefix = hex_nibble(row) <> "x: "

        cells =
          Enum.map_join(0..15, " ", fn col ->
            count = sum_cell(grid, row * 16, col * 16, 16)
            heat_char(count, max_val)
          end)

        prefix <> cells
      end)

    header <> rows <> "\n"
  end

  defp sum_cell(grid, x_start, y_start, size) do
    for x <- x_start..(x_start + size - 1),
        y <- y_start..(y_start + size - 1),
        reduce: 0 do
      acc -> acc + Map.get(grid, {x, y}, 0)
    end
  end

  defp heat_char(0, _max), do: "."
  defp heat_char(count, max) when max > 0 do
    ratio = count / max
    cond do
      ratio > 0.75 -> "█"
      ratio > 0.50 -> "▓"
      ratio > 0.25 -> "▒"
      ratio > 0.0  -> "░"
      true         -> "."
    end
  end

  defp heat_char(_, _), do: "."

  defp hex(byte), do: "0x" <> String.pad_leading(Integer.to_string(byte, 16), 2, "0")
  defp hex_nibble(n), do: Integer.to_string(n, 16)
end
