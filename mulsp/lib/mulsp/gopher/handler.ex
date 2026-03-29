defmodule Mulsp.Gopher.Handler do
  @moduledoc """
  Gopher selector routing. Maps gopher paths to internal queries.

  Selectors:
    /           → Root menu (node identity + capability overview)
    /lsp        → Available LSP methods and their route actions
    /dc         → DC transfer status, pending bloom offers
    /mesh       → Peer list with capabilities
    /finger     → This node's .plan text
    /tree       → Sparse merkin tree view (all tokens)
    /tree/<tok> → Sparse tree filtered by routing tokens
    /methods    → Full method table (local/proxy/mesh/lang)
    /partition  → Current partition config
  """

  alias Mulsp.Gopher.Server, as: G

  @doc "Handle a gopher selector, return the response body."
  def handle(selector, host, port) do
    result =
      case selector do
        "" -> root_menu(host, port)
        "/" -> root_menu(host, port)
        "/lsp" -> lsp_menu(host, port)
        "/dc" -> dc_status()
        "/mesh" -> mesh_menu(host, port)
        "/finger" -> finger_plan()
        "/methods" -> methods_table()
        "/partition" -> partition_info()
        "/tree" -> tree_view([])
        "/tree/" <> tokens -> tree_view(String.split(tokens, ","))
        _ -> not_found(selector)
      end

    result <> G.terminator()
  end

  # --- Menu Builders ---

  defp root_menu(host, port) do
    partition = get_partition()
    node_id = partition.node_id

    [
      G.info("╔══════════════════════════════════════╗"),
      G.info("║        mulsp · #{String.slice(node_id, 0..15)}"),
      G.info("║  micro universal LSP proxy servelet  "),
      G.info("╚══════════════════════════════════════╝"),
      G.info(""),
      G.info("node: #{node_id}"),
      G.info("guard: #{partition.guard_level}"),
      G.info("dc: #{partition.dc_enabled}"),
      G.info("protocols: #{Enum.join(Enum.map(partition.protocols, &to_string/1), ", ")}"),
      G.info(""),
      G.dir("LSP Methods", "/lsp", host, port),
      G.dir("DC Transfers", "/dc", host, port),
      G.dir("Mesh Peers", "/mesh", host, port),
      G.text("Finger .plan", "/finger", host, port),
      G.text("Method Table", "/methods", host, port),
      G.text("Partition Config", "/partition", host, port),
      G.dir("Merkin Tree (all)", "/tree", host, port),
      G.info("")
    ]
    |> Enum.join()
  end

  defp lsp_menu(_host, _port) do
    partition = get_partition()

    local_section =
      partition.local_methods
      |> Enum.map(fn m -> G.info("  [LOCAL] #{m}") end)
      |> Enum.join()

    mesh_section =
      partition.mesh_methods
      |> Enum.map(fn m -> G.info("  [MESH]  #{m}") end)
      |> Enum.join()

    lang_section =
      partition.lang_methods
      |> Enum.map(fn m -> G.info("  [LANG]  #{m}") end)
      |> Enum.join()

    proxy_section =
      partition.proxy_methods
      |> Enum.map(fn {m, target} -> G.info("  [PROXY] #{m} → #{target}") end)
      |> Enum.join()

    [
      G.info("=== LSP Method Routing ==="),
      G.info(""),
      G.info("-- Local Handlers --"),
      local_section,
      G.info(""),
      G.info("-- Mesh Broadcast --"),
      mesh_section,
      G.info(""),
      G.info("-- Lang Platform --"),
      lang_section,
      G.info(""),
      G.info("-- Proxy Rules --"),
      if(proxy_section == "", do: G.info("  (none)"), else: proxy_section),
      G.info("")
    ]
    |> Enum.join()
  end

  defp dc_status do
    [
      G.info("=== DC Transfer Status ==="),
      G.info(""),
      G.info("Hub: active"),
      G.info("Active transfers: 0"),
      G.info("Pending bloom offers: 0"),
      G.info("Trees cached: 0"),
      G.info("")
    ]
    |> Enum.join()
  end

  defp mesh_menu(host, port) do
    peers = Mulsp.Mesh.Cluster.peers()

    peer_lines =
      case peers do
        [] ->
          [G.info("  (no peers discovered)")]

        peers ->
          Enum.map(peers, fn {id, info} ->
            G.text("#{id} (#{info[:status]})", "/mesh/#{id}", host, port)
          end)
      end

    ([
       G.info("=== Mesh Peers ==="),
       G.info("")
     ] ++ peer_lines ++ [G.info("")])
    |> Enum.join()
  end

  defp finger_plan do
    partition = get_partition()

    plan = """
    kind: mulsp.plan
    node: #{partition.node_id}
    guard: #{partition.guard_level}
    dc: #{partition.dc_enabled}
    protocols: #{Enum.join(Enum.map(partition.protocols, &to_string/1), ",")}
    local_methods: #{length(partition.local_methods)}
    mesh_methods: #{length(partition.mesh_methods)}
    lang_methods: #{length(partition.lang_methods)}
    peers: #{map_size(Mulsp.Mesh.Cluster.peers() |> Enum.into(%{}))}
    uptime: #{System.system_time(:second)}
    """

    plan
  end

  defp methods_table do
    partition = get_partition()

    lines =
      (Enum.map(partition.local_methods, &"LOCAL  #{&1}") ++
         Enum.map(partition.mesh_methods, &"MESH   #{&1}") ++
         Enum.map(partition.lang_methods, &"LANG   #{&1}") ++
         Enum.map(partition.proxy_methods, fn {m, t} -> "PROXY  #{m} → #{t}" end))
      |> Enum.sort()
      |> Enum.join("\n")

    "METHOD TABLE\n============\n\n#{lines}\n"
  end

  defp partition_info do
    partition = get_partition()

    """
    PARTITION CONFIG
    ================

    node_id: #{partition.node_id}
    guard_level: #{partition.guard_level}
    dc_enabled: #{partition.dc_enabled}
    finger_enabled: #{partition.finger_enabled}
    lsp_enabled: #{partition.lsp_enabled}

    gopher_port: #{partition.gopher_port}
    finger_port: #{partition.finger_port}
    dc_port: #{partition.dc_port}
    lsp_port: #{partition.lsp_port}

    protocols: #{inspect(partition.protocols)}
    peer_seeds: #{inspect(partition.peer_seeds)}
    lang_host: #{partition.lang_host || "(not configured)"}
    """
  end

  defp tree_view(tokens) do
    # TODO: Query merkin Wasm bridge for sparse tree
    token_desc = if tokens == [], do: "all", else: Enum.join(tokens, ", ")

    """
    SPARSE MERKIN TREE VIEW
    =======================
    tokens: #{token_desc}
    nodes: (merkin wasm bridge not yet connected)
    """
  end

  defp not_found(selector) do
    G.error("Not found: #{selector}")
  end

  defp get_partition do
    case GenServer.whereis(Mulsp.Dispatch) do
      nil -> Mulsp.Partition.load()
      _pid -> Mulsp.Dispatch |> :sys.get_state() |> Map.get(:partition)
    end
  end
end
