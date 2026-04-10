defmodule Muyata.Observer.Census do
  @moduledoc """
  Message type classification and counting.

  Once framing produces discrete messages, Census classifies them by:
  - Tag byte (first byte of each message)
  - Length distribution per tag
  - Shannon entropy per message type
  - Direction (client vs server)
  - Sequence patterns (which tags follow which)

  Each new distinct pattern becomes a node in the merkin tree.
  State is a map of tag_byte => observation stats.
  """
  use GenServer

  defmodule Pattern do
    @moduledoc false
    defstruct [
      :tag,
      count: 0,
      total_bytes: 0,
      min_len: nil,
      max_len: nil,
      directions: %{client: 0, server: 0},
      last_seen: nil
    ]
  end

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Classify a framed message."
  def classify(direction, message) when is_binary(message) do
    GenServer.cast(__MODULE__, {:classify, direction, message})
  end

  @doc "Get all observed patterns."
  def patterns do
    GenServer.call(__MODULE__, :patterns)
  end

  @doc "Get pattern count."
  def count do
    GenServer.call(__MODULE__, :count)
  end

  @impl true
  def init(_opts) do
    {:ok, %{patterns: %{}, last_tag: nil, transitions: %{}}}
  end

  @impl true
  def handle_cast({:classify, direction, message}, state) do
    tag = extract_tag(message)
    len = byte_size(message)
    now = System.system_time(:second)

    {is_new, patterns} = update_pattern(state.patterns, tag, direction, len, now)
    transitions = update_transitions(state.transitions, state.last_tag, tag)

    if is_new do
      Muyata.Void.new_pattern()
      Muyata.Substrate.Tree.ingest(tag_to_token(tag), ["message_type", tag_to_hex(tag)])
      Muyata.Substrate.Bloom.add(tag_to_token(tag))
    end

    {:noreply, %{state | patterns: patterns, last_tag: tag, transitions: transitions}}
  end

  @impl true
  def handle_call(:patterns, _from, state) do
    result =
      state.patterns
      |> Enum.map(fn {tag, p} ->
        %{
          tag: tag_to_hex(tag),
          count: p.count,
          avg_len: safe_div(p.total_bytes, p.count),
          min_len: p.min_len,
          max_len: p.max_len,
          directions: p.directions,
          follows: Map.get(state.transitions, tag, %{})
        }
      end)
      |> Enum.sort_by(& &1.count, :desc)

    {:reply, result, state}
  end

  def handle_call(:count, _from, state) do
    {:reply, map_size(state.patterns), state}
  end

  defp extract_tag(<<tag::8, _rest::binary>>), do: tag
  defp extract_tag(<<>>), do: 0

  defp update_pattern(patterns, tag, direction, len, now) do
    case Map.get(patterns, tag) do
      nil ->
        pattern = %Pattern{
          tag: tag,
          count: 1,
          total_bytes: len,
          min_len: len,
          max_len: len,
          directions: %{direction => 1},
          last_seen: now
        }

        {true, Map.put(patterns, tag, pattern)}

      existing ->
        updated = %{
          existing
          | count: existing.count + 1,
            total_bytes: existing.total_bytes + len,
            min_len: min(existing.min_len, len),
            max_len: max(existing.max_len, len),
            directions: Map.update(existing.directions, direction, 1, &(&1 + 1)),
            last_seen: now
        }

        {false, Map.put(patterns, tag, updated)}
    end
  end

  defp update_transitions(transitions, nil, _to), do: transitions

  defp update_transitions(transitions, from, to) do
    Map.update(transitions, from, %{to => 1}, fn follows ->
      Map.update(follows, to, 1, &(&1 + 1))
    end)
  end

  defp tag_to_hex(tag), do: "0x" <> Integer.to_string(tag, 16) |> String.pad_leading(4, "0x")
  defp tag_to_token(tag), do: "msg_type_#{Integer.to_string(tag, 16)}"
  defp safe_div(_n, 0), do: 0
  defp safe_div(n, d), do: div(n, d)
end
