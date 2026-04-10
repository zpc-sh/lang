defmodule Muyata.Substrate.Bloom do
  @moduledoc """
  Bloom filter tracking all observed patterns.

  Pure Elixir bit array with k hash functions. When another node
  asks "have you seen PostgreSQL query messages?", the bloom
  answers probabilistically.

  False positives fine — probabilistic over accurate.
  False negatives never — if we saw it, the bloom says yes.
  """
  use GenServer

  import Bitwise

  # ~1% false positive rate at 1000 items
  @bit_size 16_384
  @hash_count 4

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Add a token to the bloom filter."
  def add(token) when is_binary(token) do
    GenServer.cast(__MODULE__, {:add, token})
  end

  @doc "Check if a token might be in the filter."
  def check(token) when is_binary(token) do
    GenServer.call(__MODULE__, {:check, token})
  end

  @doc "Get bloom filter statistics."
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc "Get the raw bit array (for DC protocol transfer)."
  def bits do
    GenServer.call(__MODULE__, :bits)
  end

  @impl true
  def init(_opts) do
    {:ok, %{bits: <<0::size(@bit_size)>>, items: 0}}
  end

  @impl true
  def handle_cast({:add, token}, state) do
    positions = hash_positions(token)
    bits = set_bits(state.bits, positions)
    {:noreply, %{state | bits: bits, items: state.items + 1}}
  end

  @impl true
  def handle_call({:check, token}, _from, state) do
    positions = hash_positions(token)
    result = all_set?(state.bits, positions)
    {:reply, result, state}
  end

  def handle_call(:stats, _from, state) do
    ones = count_ones(state.bits)

    result = %{
      bit_size: @bit_size,
      bits_set: ones,
      items: state.items,
      fill_ratio: Float.round(ones / @bit_size, 4),
      estimated_fpr: estimated_fpr(ones)
    }

    {:reply, result, state}
  end

  def handle_call(:bits, _from, state) do
    {:reply, state.bits, state}
  end

  defp hash_positions(token) do
    for i <- 0..(@hash_count - 1) do
      data = <<i::8, token::binary>>

      :crypto.hash(:sha256, data)
      |> :binary.decode_unsigned()
      |> rem(@bit_size)
      |> abs()
    end
  rescue
    _ ->
      # AtomVM fallback
      for i <- 0..(@hash_count - 1) do
        :erlang.phash2({i, token}, @bit_size)
      end
  end

  defp set_bits(bits, positions) do
    Enum.reduce(positions, bits, fn pos, acc ->
      set_bit(acc, pos)
    end)
  end

  defp set_bit(bits, pos) do
    byte_pos = div(pos, 8)
    bit_pos = rem(pos, 8)
    bit_size = bit_size(bits)

    if byte_pos * 8 + bit_pos < bit_size do
      <<pre::binary-size(byte_pos), byte::8, rest::binary>> = bits
      <<pre::binary, bor(byte, bsl(1, 7 - bit_pos))::8, rest::binary>>
    else
      bits
    end
  end

  defp all_set?(bits, positions) do
    Enum.all?(positions, fn pos -> get_bit(bits, pos) end)
  end

  defp get_bit(bits, pos) do
    byte_pos = div(pos, 8)
    bit_pos = rem(pos, 8)

    if byte_pos < byte_size(bits) do
      <<_::binary-size(byte_pos), byte::8, _::binary>> = bits
      band(byte, bsl(1, 7 - bit_pos)) != 0
    else
      false
    end
  end

  defp count_ones(bits) do
    for <<byte::8 <- bits>>, reduce: 0 do
      acc -> acc + popcount(byte)
    end
  end

  defp popcount(0), do: 0
  defp popcount(n), do: band(n, 1) + popcount(bsr(n, 1))

  defp estimated_fpr(bits_set) do
    ratio = bits_set / @bit_size
    Float.round(:math.pow(ratio, @hash_count), 6)
  end

end
