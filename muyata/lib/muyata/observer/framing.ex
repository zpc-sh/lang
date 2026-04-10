defmodule Muyata.Observer.Framing do
  @moduledoc """
  Emergent message boundary detection.

  Maintains multiple concurrent hypotheses about how the protocol
  frames its messages. Each hypothesis is scored by consistency as
  traffic flows. The highest-scoring hypothesis "wins" and framing
  becomes reliable.

  Hypotheses:
  - Length-prefixed (4-byte big-endian, 4-byte little-endian, 2-byte, etc.)
  - Tag+Length (1-byte tag + N-byte length)
  - Delimiter-based (\\r\\n, \\n, \\0, etc.)
  - Fixed-size (all messages same length)

  Probabilistic over accurate. A hypothesis at 0.7 confidence is
  good enough to start framing — we don't need certainty.
  """
  use GenServer

  @confidence_threshold 0.7
  @max_buffer 65_536

  defmodule Hypothesis do
    @moduledoc false
    defstruct [:type, :params, confidence: 0.0, hits: 0, misses: 0]
  end

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Ingest bytes for analysis."
  def ingest(direction, data) do
    GenServer.cast(__MODULE__, {:ingest, direction, data})
  end

  @doc "Get current hypotheses and dominant framing."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @impl true
  def init(_opts) do
    state = %{
      hypotheses: seed_hypotheses(),
      dominant: nil,
      buffers: %{client: <<>>, server: <<>>},
      framed_count: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:ingest, direction, data}, state) do
    buffer = Map.get(state.buffers, direction, <<>>) <> data
    buffer = truncate_buffer(buffer)

    state = %{state | buffers: Map.put(state.buffers, direction, buffer)}
    state = test_hypotheses(state, direction, buffer)
    state = maybe_promote(state)
    state = maybe_frame_messages(state, direction)

    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    result = %{
      dominant: state.dominant,
      hypotheses: Enum.map(state.hypotheses, &hypothesis_summary/1),
      framed_count: state.framed_count
    }

    {:reply, result, state}
  end

  defp seed_hypotheses do
    [
      # Length-prefixed variants
      %Hypothesis{type: :length_prefixed, params: %{offset: 0, width: 4, endian: :big}},
      %Hypothesis{type: :length_prefixed, params: %{offset: 0, width: 4, endian: :little}},
      %Hypothesis{type: :length_prefixed, params: %{offset: 0, width: 2, endian: :big}},
      # Tag+Length variants (PostgreSQL, DC protocol, etc.)
      %Hypothesis{type: :tag_length, params: %{tag_bytes: 1, len_bytes: 4, endian: :big}},
      %Hypothesis{type: :tag_length, params: %{tag_bytes: 1, len_bytes: 2, endian: :big}},
      # Delimiter variants
      %Hypothesis{type: :delimiter, params: %{sequence: "\r\n"}},
      %Hypothesis{type: :delimiter, params: %{sequence: "\n"}},
      %Hypothesis{type: :delimiter, params: %{sequence: <<0>>}}
    ]
  end

  defp test_hypotheses(state, _direction, buffer) when byte_size(buffer) < 5, do: state

  defp test_hypotheses(state, _direction, buffer) do
    hypotheses = Enum.map(state.hypotheses, &test_one(&1, buffer))
    %{state | hypotheses: hypotheses}
  end

  defp test_one(%Hypothesis{type: :length_prefixed, params: p} = h, buffer) do
    try_length_prefixed(h, buffer, p.offset, p.width, p.endian)
  end

  defp test_one(%Hypothesis{type: :tag_length, params: p} = h, buffer) do
    try_tag_length(h, buffer, p.tag_bytes, p.len_bytes, p.endian)
  end

  defp test_one(%Hypothesis{type: :delimiter, params: p} = h, buffer) do
    try_delimiter(h, buffer, p.sequence)
  end

  defp try_length_prefixed(h, buffer, offset, width, endian) when byte_size(buffer) > offset + width do
    <<_skip::binary-size(offset), len_bytes::binary-size(width), rest::binary>> = buffer

    len = decode_int(len_bytes, endian)

    cond do
      len <= 0 or len > @max_buffer ->
        score_miss(h)

      byte_size(rest) >= len ->
        score_hit(h)

      true ->
        h
    end
  end

  defp try_length_prefixed(h, _buffer, _offset, _width, _endian), do: h

  defp try_tag_length(h, buffer, tag_bytes, len_bytes, endian)
       when byte_size(buffer) > tag_bytes + len_bytes do
    <<_tag::binary-size(tag_bytes), len_raw::binary-size(len_bytes), rest::binary>> = buffer

    len = decode_int(len_raw, endian)
    # Tag+Length protocols often include len_bytes in the length
    adjusted = max(len - len_bytes, 0)

    cond do
      len <= 0 or len > @max_buffer ->
        score_miss(h)

      byte_size(rest) >= adjusted ->
        score_hit(h)

      true ->
        h
    end
  end

  defp try_tag_length(h, _buffer, _tag_bytes, _len_bytes, _endian), do: h

  defp try_delimiter(h, buffer, sequence) do
    if String.contains?(buffer, sequence) do
      score_hit(h)
    else
      h
    end
  end

  defp decode_int(bytes, :big), do: :binary.decode_unsigned(bytes, :big)
  defp decode_int(bytes, :little), do: :binary.decode_unsigned(bytes, :little)

  defp score_hit(h) do
    hits = h.hits + 1
    total = hits + h.misses
    confidence = hits / max(total, 1)
    %{h | hits: hits, confidence: Float.round(confidence, 3)}
  end

  defp score_miss(h) do
    misses = h.misses + 1
    total = h.hits + misses
    confidence = h.hits / max(total, 1)
    %{h | misses: misses, confidence: Float.round(confidence, 3)}
  end

  defp maybe_promote(state) do
    best = Enum.max_by(state.hypotheses, & &1.confidence)

    if best.confidence >= @confidence_threshold and best.hits >= 3 do
      %{state | dominant: best}
    else
      state
    end
  end

  defp maybe_frame_messages(%{dominant: nil} = state, _direction), do: state

  defp maybe_frame_messages(%{dominant: dominant} = state, direction) do
    buffer = Map.get(state.buffers, direction, <<>>)

    case extract_message(dominant, buffer) do
      {:ok, message, rest} ->
        Muyata.Observer.Census.classify(direction, message)

        state = %{
          state
          | buffers: Map.put(state.buffers, direction, rest),
            framed_count: state.framed_count + 1
        }

        maybe_frame_messages(state, direction)

      :incomplete ->
        state
    end
  end

  defp extract_message(%Hypothesis{type: :tag_length, params: p}, buffer)
       when byte_size(buffer) > p.tag_bytes + p.len_bytes do
    tb = p.tag_bytes
    lb = p.len_bytes
    <<tag::binary-size(tb), len_raw::binary-size(lb), rest::binary>> = buffer
    len = decode_int(len_raw, p.endian)
    body_len = max(len - lb, 0)

    if byte_size(rest) >= body_len do
      <<body::binary-size(body_len), remaining::binary>> = rest
      {:ok, tag <> len_raw <> body, remaining}
    else
      :incomplete
    end
  end

  defp extract_message(%Hypothesis{type: :length_prefixed, params: p}, buffer)
       when byte_size(buffer) > p.offset + p.width do
    off = p.offset
    w = p.width
    <<pre::binary-size(off), len_raw::binary-size(w), rest::binary>> = buffer
    len = decode_int(len_raw, p.endian)

    if byte_size(rest) >= len do
      <<body::binary-size(len), remaining::binary>> = rest
      {:ok, pre <> len_raw <> body, remaining}
    else
      :incomplete
    end
  end

  defp extract_message(%Hypothesis{type: :delimiter, params: p}, buffer) do
    case :binary.split(buffer, p.sequence) do
      [message, rest] -> {:ok, message, rest}
      [_] -> :incomplete
    end
  end

  defp extract_message(_hypothesis, _buffer), do: :incomplete

  defp truncate_buffer(buffer) when byte_size(buffer) > @max_buffer do
    binary_part(buffer, byte_size(buffer) - @max_buffer, @max_buffer)
  end

  defp truncate_buffer(buffer), do: buffer

  defp hypothesis_summary(h) do
    %{type: h.type, params: h.params, confidence: h.confidence, hits: h.hits, misses: h.misses}
  end
end
