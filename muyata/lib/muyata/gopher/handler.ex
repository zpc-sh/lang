defmodule Muyata.Gopher.Handler do
  @moduledoc """
  Gopher selector routing for muyata.

  Selectors:
  - / or ""  → root menu (void status, navigation)
  - /void    → current void state
  - /framing → detected framing hypotheses
  - /patterns → classified message types
  - /heatmap → ASCII heatmap of protocol coverage
  - /tree    → merkin tree summary
  - /epochs  → sealed epoch list
  - /bloom   → bloom filter statistics
  - /shape   → current sealed shape
  - /mesh    → mesh peer status
  """
  alias Muyata.Gopher.Server, as: G

  def handle(selector, host, port) do
    selector = if selector == "", do: "/", else: selector

    case selector do
      "/" -> root_menu(host, port)
      "/void" -> void_status()
      "/framing" -> framing_status()
      "/patterns" -> pattern_list()
      "/heatmap" -> heatmap_view()
      "/tree" -> tree_view()
      "/epochs" -> epoch_list()
      "/bloom" -> bloom_stats()
      "/shape" -> shape_view()
      "/mesh" -> mesh_view()
      _ -> G.error("Not found: #{selector}") <> G.terminator()
    end
  end

  defp root_menu(host, port) do
    void = Muyata.Void.state()

    [
      G.info(""),
      G.info("  muyata — the emptiness"),
      G.info("  node: #{void.node_id}"),
      G.info("  target: #{void.upstream_host}:#{void.upstream_port}"),
      G.info("  listen: #{void.listen_port}"),
      G.info("  epoch: #{void.epoch} | patterns: #{void.patterns_seen} | bytes: #{format_bytes(void.bytes_observed)}"),
      G.info(""),
      G.dir("Void State", "/void", host, port),
      G.dir("Framing Hypotheses", "/framing", host, port),
      G.dir("Message Patterns", "/patterns", host, port),
      G.text("Coverage Heatmap", "/heatmap", host, port),
      G.dir("Merkin Tree", "/tree", host, port),
      G.dir("Sealed Epochs", "/epochs", host, port),
      G.dir("Bloom Filter", "/bloom", host, port),
      G.text("Current Shape", "/shape", host, port),
      G.dir("Mesh Peers", "/mesh", host, port),
      G.info(""),
      G.terminator()
    ]
    |> IO.iodata_to_binary()
  end

  defp void_status do
    void = Muyata.Void.state()

    lines = [
      G.info("VOID STATE"),
      G.info(""),
      G.info("node_id: #{void.node_id}"),
      G.info("listen_port: #{void.listen_port}"),
      G.info("upstream: #{void.upstream_host}:#{void.upstream_port}"),
      G.info("epoch: #{void.epoch}"),
      G.info("patterns_seen: #{void.patterns_seen}"),
      G.info("bytes_observed: #{format_bytes(void.bytes_observed)}"),
      G.info("connections_seen: #{void.connections_seen}"),
      G.info(""),
      G.terminator()
    ]

    IO.iodata_to_binary(lines)
  end

  defp framing_status do
    status = Muyata.Observer.Framing.status()

    dominant_line =
      case status.dominant do
        nil -> G.info("dominant: none (still learning)")
        d -> G.info("dominant: #{d.type} @ #{d.confidence} confidence")
      end

    hypothesis_lines =
      Enum.map(status.hypotheses, fn h ->
        G.info("  #{h.type} #{inspect(h.params)} — #{h.confidence} (#{h.hits}h/#{h.misses}m)")
      end)

    lines =
      [
        G.info("FRAMING HYPOTHESES"),
        G.info(""),
        dominant_line,
        G.info("framed_count: #{status.framed_count}"),
        G.info(""),
        G.info("All hypotheses:")
      ] ++ hypothesis_lines ++ [G.info(""), G.terminator()]

    IO.iodata_to_binary(lines)
  end

  defp pattern_list do
    patterns = Muyata.Observer.Census.patterns()

    pattern_lines =
      Enum.map(patterns, fn p ->
        dir = if p.directions[:client] > (p.directions[:server] || 0), do: "→", else: "←"
        G.info("  #{p.tag} #{dir}  count:#{p.count}  avg:#{p.avg_len}b  range:#{p.min_len}-#{p.max_len}b")
      end)

    lines =
      [
        G.info("MESSAGE PATTERNS (#{length(patterns)} types)"),
        G.info("")
      ] ++ pattern_lines ++ [G.info(""), G.terminator()]

    IO.iodata_to_binary(lines)
  end

  defp heatmap_view do
    ascii = Muyata.Observer.Heatmap.render_ascii()
    coverage = Muyata.Observer.Heatmap.coverage()

    "COVERAGE HEATMAP (#{Float.round(coverage * 100, 2)}% observed)\n\n#{ascii}\n.\r\n"
  end

  defp tree_view do
    stats = Muyata.Substrate.Tree.stats()

    lines = [
      G.info("MERKIN TREE"),
      G.info(""),
      G.info("nodes: #{stats.node_count}"),
      G.info("tokens: #{stats.token_count}"),
      G.info("root_hash: #{stats.root_hash || "nil (empty)"}"),
      G.info("sealed_epochs: #{stats.sealed_epochs}"),
      G.info(""),
      G.terminator()
    ]

    IO.iodata_to_binary(lines)
  end

  defp epoch_list do
    epochs = Muyata.Substrate.Epoch.epochs()

    epoch_lines =
      Enum.map(epochs, fn e ->
        G.info("  epoch #{e.epoch}: #{e.nodes} nodes, #{e.patterns} patterns, #{Float.round(e.coverage * 100, 4)}% coverage")
      end)

    lines =
      [G.info("SEALED EPOCHS (#{length(epochs)})"), G.info("")]
      ++ epoch_lines
      ++ [G.info(""), G.terminator()]

    IO.iodata_to_binary(lines)
  end

  defp bloom_stats do
    stats = Muyata.Substrate.Bloom.stats()

    lines = [
      G.info("BLOOM FILTER"),
      G.info(""),
      G.info("bit_size: #{stats.bit_size}"),
      G.info("bits_set: #{stats.bits_set}"),
      G.info("items: #{stats.items}"),
      G.info("fill_ratio: #{stats.fill_ratio}"),
      G.info("estimated_fpr: #{stats.estimated_fpr}"),
      G.info(""),
      G.terminator()
    ]

    IO.iodata_to_binary(lines)
  end

  defp shape_view do
    shape = Muyata.Shape.seal()
    types = map_size(shape.message_types)

    "CURRENT SHAPE: #{shape.name}\nframing: #{inspect(shape.framing)}\nmessage_types: #{types}\ncoverage: #{Float.round(shape.coverage * 100, 4)}%\ntree_hash: #{shape.tree_hash || "nil"}\nepoch: #{shape.epoch}\n.\r\n"
  end

  defp mesh_view do
    peers = Muyata.Mesh.Cluster.peers()

    peer_lines =
      Enum.map(peers, fn p ->
        G.info("  #{p.id} (#{p.type}) @ #{p.host}:#{p.port}")
      end)

    lines =
      [G.info("MESH PEERS (#{length(peers)})"), G.info("")]
      ++ peer_lines
      ++ [G.info(""), G.terminator()]

    IO.iodata_to_binary(lines)
  end

  defp format_bytes(0), do: "0"
  defp format_bytes(b) when b < 1024, do: "#{b}B"
  defp format_bytes(b) when b < 1_048_576, do: "#{Float.round(b / 1024, 1)}KB"
  defp format_bytes(b) when b < 1_073_741_824, do: "#{Float.round(b / 1_048_576, 1)}MB"
  defp format_bytes(b), do: "#{Float.round(b / 1_073_741_824, 1)}GB"
end
