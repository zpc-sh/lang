defmodule Mulsp.DC.Protocol do
  @moduledoc """
  Direct Connect protocol for AI-to-AI sparse merkin tree transfers.

  This is the critical innovation: AI agents doing mass-scale work produce
  and consume sparse merkin trees at high velocity. A code review, a security
  triage, a migration — each is a sparse tree that needs to move FAST between
  agents. Probabilistic and rapid, not accurate.

  Flow:
  1. Sender builds SparseMerkinTree from their work
  2. Sender sends BloomOffer with the tree's routing sketch
  3. Receiver checks bloom against own tree — Accept or Reject
  4. On accept: chunked TreeBegin → N × TreeChunk → TreeEnd
  5. Receiver merges via diff

  Message format: 1-byte type tag + payload (Erlang ETF)
  No JSON. No HTTP. No overhead.
  """

  # Message type tags
  @bloom_offer 0x01
  @bloom_request 0x02
  @bloom_accept 0x03
  @bloom_reject 0x04
  @tree_begin 0x10
  @tree_chunk 0x11
  @tree_end 0x12
  @diff_begin 0x20
  @diff_payload 0x21
  @diff_end 0x22
  @ping 0xF0
  @pong 0xF1
  @bye 0xFF

  @doc "Encode a DC message to binary."
  def encode(message) do
    {tag, payload} = message_to_tagged(message)
    body = :erlang.term_to_binary(payload)
    <<tag::8, byte_size(body)::32, body::binary>>
  end

  @doc "Decode a DC message from binary. Returns {:ok, message, rest} or {:incomplete, buffer}."
  def decode(<<tag::8, length::32, rest::binary>>) when byte_size(rest) >= length do
    <<payload_bytes::binary-size(length), remaining::binary>> = rest
    payload = :erlang.binary_to_term(payload_bytes)
    message = tagged_to_message(tag, payload)
    {:ok, message, remaining}
  end

  def decode(buffer) when is_binary(buffer), do: {:incomplete, buffer}

  # --- Message constructors ---

  def bloom_offer(sketch_bits, token_count) do
    {:bloom_offer, %{sketch: sketch_bits, tokens: token_count}}
  end

  def bloom_request(tokens) do
    {:bloom_request, %{tokens: tokens}}
  end

  def bloom_accept, do: {:bloom_accept, %{}}
  def bloom_reject, do: {:bloom_reject, %{}}

  def tree_begin(tree_hash, node_count) do
    {:tree_begin, %{hash: tree_hash, nodes: node_count}}
  end

  def tree_chunk(index, nodes) do
    {:tree_chunk, %{index: index, nodes: nodes}}
  end

  def tree_end(tree_hash) do
    {:tree_end, %{hash: tree_hash}}
  end

  def diff_begin(base_hash) do
    {:diff_begin, %{base: base_hash}}
  end

  def diff_payload(added, removed, changed, unchanged) do
    {:diff_payload, %{added: added, removed: removed, changed: changed, unchanged: unchanged}}
  end

  def diff_end, do: {:diff_end, %{}}

  def ping, do: {:ping, %{}}
  def pong, do: {:pong, %{}}
  def bye, do: {:bye, %{}}

  # --- Internal encoding ---

  defp message_to_tagged({:bloom_offer, p}), do: {@bloom_offer, p}
  defp message_to_tagged({:bloom_request, p}), do: {@bloom_request, p}
  defp message_to_tagged({:bloom_accept, p}), do: {@bloom_accept, p}
  defp message_to_tagged({:bloom_reject, p}), do: {@bloom_reject, p}
  defp message_to_tagged({:tree_begin, p}), do: {@tree_begin, p}
  defp message_to_tagged({:tree_chunk, p}), do: {@tree_chunk, p}
  defp message_to_tagged({:tree_end, p}), do: {@tree_end, p}
  defp message_to_tagged({:diff_begin, p}), do: {@diff_begin, p}
  defp message_to_tagged({:diff_payload, p}), do: {@diff_payload, p}
  defp message_to_tagged({:diff_end, p}), do: {@diff_end, p}
  defp message_to_tagged({:ping, p}), do: {@ping, p}
  defp message_to_tagged({:pong, p}), do: {@pong, p}
  defp message_to_tagged({:bye, p}), do: {@bye, p}

  defp tagged_to_message(@bloom_offer, p), do: {:bloom_offer, p}
  defp tagged_to_message(@bloom_request, p), do: {:bloom_request, p}
  defp tagged_to_message(@bloom_accept, p), do: {:bloom_accept, p}
  defp tagged_to_message(@bloom_reject, p), do: {:bloom_reject, p}
  defp tagged_to_message(@tree_begin, p), do: {:tree_begin, p}
  defp tagged_to_message(@tree_chunk, p), do: {:tree_chunk, p}
  defp tagged_to_message(@tree_end, p), do: {:tree_end, p}
  defp tagged_to_message(@diff_begin, p), do: {:diff_begin, p}
  defp tagged_to_message(@diff_payload, p), do: {:diff_payload, p}
  defp tagged_to_message(@diff_end, p), do: {:diff_end, p}
  defp tagged_to_message(@ping, p), do: {:ping, p}
  defp tagged_to_message(@pong, p), do: {:pong, p}
  defp tagged_to_message(@bye, p), do: {:bye, p}
  defp tagged_to_message(tag, p), do: {:unknown, %{tag: tag, payload: p}}
end
