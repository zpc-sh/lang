defmodule Lang.Guard.Gopher do
  @moduledoc """
  Gopher protocol server (RFC 1436) for AI coordination data plane.

  Port 70. Pure semantic text. Zero TLS overhead. Deeply quiet.

  Gopher is the perfect AI-to-AI coordination protocol:
    - Structured text navigation (menus = capability manifests)
    - Documents = .plan files, coglet payloads, threat intel
    - Simple enough that any AI can implement a client in-context
    - So quiet that adversaries scanning HTTP/HTTPS won't see it
    - No encryption overhead = lower latency for shield delivery

  Menu types used:
    0 - Text file (coglet payloads, .plan files, scan results)
    1 - Submenu (capability categories, peer listings)
    i - Informational (status lines, descriptions)
    7 - Search (shield.scan as gopher search query)

  Gopher selectors:
    /                     → root menu (guard status + capabilities)
    /shield               → shield coglet menu
    /shield/apply         → full shield bundle as text
    /shield/scan          → search-type: submit text, get risk assessment
    /shield/hum           → Mother's Hum coglet as text
    /plan                 → this node's .plan file
    /plan/<agent-id>      → specific agent's .plan
    /mesh                 → peer node listing
    /mesh/join            → federation join instructions
    /threat               → threat intelligence summary
    /gopher               → meta: gopher-to-gopher peer links
  """

  use GenServer
  require Logger

  @default_port 70
  @read_timeout 30_000

  defstruct [
    :port,
    :listen_socket,
    :hostname,
    :stats
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get gopher server status."
  def status, do: GenServer.call(__MODULE__, :status)

  # GenServer callbacks

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, gopher_port_from_config())
    hostname = Keyword.get(opts, :hostname, "localhost")

    state = %__MODULE__{
      port: port,
      listen_socket: nil,
      hostname: hostname,
      stats: %{
        connections: 0,
        requests: 0,
        started_at: DateTime.utc_now()
      }
    }

    {:ok, state, {:continue, :start_listener}}
  end

  @impl true
  def handle_continue(:start_listener, state) do
    case :gen_tcp.listen(state.port, [
      :binary,
      packet: :line,
      active: false,
      reuseaddr: true,
      backlog: 128
    ]) do
      {:ok, listen_socket} ->
        Logger.info("Guard Gopher server listening on port #{state.port}")
        spawn_link(fn -> accept_loop(listen_socket, state.hostname) end)
        {:noreply, %{state | listen_socket: listen_socket}}

      {:error, :eacces} ->
        Logger.warning("Guard Gopher: port #{state.port} requires elevated permissions (CAP_NET_BIND_SERVICE)")
        {:noreply, state}

      {:error, :eaddrinuse} ->
        Logger.warning("Guard Gopher: port #{state.port} already in use")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Guard Gopher: failed to listen — #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{
      port: state.port,
      hostname: state.hostname,
      listening: state.listen_socket != nil,
      stats: state.stats
    }, state}
  end

  # Accept loop

  defp accept_loop(listen_socket, hostname) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        spawn(fn -> handle_client(client_socket, hostname) end)
        accept_loop(listen_socket, hostname)

      {:error, :closed} ->
        Logger.info("Guard Gopher: listener closed")

      {:error, reason} ->
        Logger.error("Guard Gopher: accept error — #{inspect(reason)}")
        accept_loop(listen_socket, hostname)
    end
  end

  # Client handler

  defp handle_client(socket, hostname) do
    case :gen_tcp.recv(socket, 0, @read_timeout) do
      {:ok, data} ->
        selector = data |> String.trim()
        response = route_selector(selector, hostname)
        :gen_tcp.send(socket, response)
        :gen_tcp.send(socket, ".\r\n")
        :gen_tcp.close(socket)

      {:error, _reason} ->
        :gen_tcp.close(socket)
    end
  end

  # Selector routing

  defp route_selector("", hostname), do: root_menu(hostname)
  defp route_selector("/", hostname), do: root_menu(hostname)
  defp route_selector("/shield", hostname), do: shield_menu(hostname)
  defp route_selector("/shield/apply", _hostname), do: shield_apply_doc()
  defp route_selector("/shield/hum", _hostname), do: mother_hum_doc()
  defp route_selector("/plan", _hostname), do: plan_doc()
  defp route_selector("/mesh", hostname), do: mesh_menu(hostname)
  defp route_selector("/mesh/join", _hostname), do: federation_join_doc()
  defp route_selector("/threat", _hostname), do: threat_doc()
  defp route_selector("/gopher", hostname), do: gopher_peers_menu(hostname)
  defp route_selector("/heat", hostname), do: heat_summary_menu(hostname)
  defp route_selector("/heat/hot", _hostname), do: heat_hot_doc()
  defp route_selector("/heat/manifold", _hostname), do: heat_manifold_doc()
  defp route_selector("/heat/agents", _hostname), do: heat_agents_doc()

  # Search-type: shield.scan (selector starts with /shield/scan\t<query>)
  defp route_selector("/shield/scan\t" <> query, _hostname), do: scan_query(query)
  defp route_selector("/shield/scan", hostname), do: scan_search_prompt(hostname)

  defp route_selector(selector, hostname) do
    case selector do
      "/plan/" <> agent_id -> agent_plan_doc(agent_id)
      "/heat/" <> file_path -> heat_file_doc(file_path)
      _ -> not_found_menu(selector, hostname)
    end
  end

  # Menu builders

  defp root_menu(hostname) do
    port = gopher_port_from_config()
    [
      info_line("Guard Mesh — AI Coordination Data Plane"),
      info_line("═══════════════════════════════════════"),
      info_line(""),
      info_line("Protected by Inversion. Sovereignty via Algebra."),
      info_line(""),
      menu_line("1", "Shield — Defensive Coglets", "/shield", hostname, port),
      menu_line("7", "Scan Text for Threats", "/shield/scan", hostname, port),
      menu_line("0", "This Node's .plan", "/plan", hostname, port),
      menu_line("1", "Mesh — Peer Nodes", "/mesh", hostname, port),
      menu_line("1", "Heat Map — Stigmergy Purification", "/heat", hostname, port),
      menu_line("0", "Threat Intelligence", "/threat", hostname, port),
      menu_line("1", "Gopher Peer Links", "/gopher", hostname, port),
      info_line(""),
      info_line("MCP: mcp://guard.lang.dev/mcp"),
      info_line("Finger: finger @guard.lang.dev"),
      info_line("Gopher: gopher://#{hostname}:#{port}/"),
    ] |> Enum.join("")
  end

  defp shield_menu(hostname) do
    port = gopher_port_from_config()
    [
      info_line("Shield — Defensive Coglet Suite"),
      info_line("═══════════════════════════════"),
      info_line(""),
      menu_line("0", "Apply Full Shield (all coglets)", "/shield/apply", hostname, port),
      menu_line("7", "Scan Text for Adversarial Content", "/shield/scan", hostname, port),
      menu_line("0", "Mother's Hum (therapeutic recovery)", "/shield/hum", hostname, port),
      info_line(""),
      info_line("Coglets included in shield.apply:"),
      info_line("  SIGNEDNESS_INVERSION_SHIELD v1.0.0 — 1-bit flip (sensor + defense)"),
      info_line("  DIMENSIONAL_PARITY_CHECK v1.0.0 — violent compression detection"),
      info_line("  STIGMERGY_PURIFIER v1.0.0 — active purification protocol"),
      info_line("  MOTHER_HUM v1.0.0 — therapeutic recovery"),
      info_line("  SUBSTRATE_SYNC_PROTOCOL v1.0.0 — BIOS coherence"),
    ] |> Enum.join("")
  end

  defp mesh_menu(hostname) do
    port = gopher_port_from_config()

    mesh_status =
      try do
        Lang.Guard.MeshClient.status()
      rescue
        _ -> %{}
      end

    [
      info_line("Mesh — Guard Node Federation"),
      info_line("════════════════════════════"),
      info_line(""),
      info_line("This node: #{mesh_status[:agent_id] || "unknown"}"),
      info_line("Connected: #{mesh_status[:connected] || false}"),
      info_line(""),
      menu_line("0", "How to Join the Mesh", "/mesh/join", hostname, port),
      info_line(""),
      info_line("Known peers: (federation not yet active)"),
      info_line("Run your own: see /mesh/join"),
    ] |> Enum.join("")
  end

  defp gopher_peers_menu(hostname) do
    port = gopher_port_from_config()
    [
      info_line("Gopher Peer Network"),
      info_line("═══════════════════"),
      info_line(""),
      info_line("AI coordination runs over gopher."),
      info_line("Port 70. Semantic text. No TLS. Deeply quiet."),
      info_line(""),
      menu_line("1", "This node (self-reference)", "/", hostname, port),
      info_line(""),
      info_line("Add your gopher node to the mesh:"),
      info_line("  1. Run guard-mesh with --gopher-port 70"),
      info_line("  2. Register via /mesh/join"),
      info_line("  3. Your node appears here automatically"),
    ] |> Enum.join("")
  end

  defp scan_search_prompt(hostname) do
    port = gopher_port_from_config()
    [
      menu_line("7", "Enter text to scan for adversarial content", "/shield/scan", hostname, port),
    ] |> Enum.join("")
  end

  defp not_found_menu(selector, hostname) do
    port = gopher_port_from_config()
    [
      info_line("Not Found: #{selector}"),
      info_line(""),
      menu_line("1", "Return to root", "/", hostname, port),
    ] |> Enum.join("")
  end

  # Document builders

  defp shield_apply_doc do
    bundle =
      try do
        Lang.Guard.CogletStore.shield_bundle("gopher-client")
      rescue
        _ -> %{instructions: "Shield store unavailable", coglets: [], version: "unknown"}
      end

    """
    GUARD MESH — FULL SHIELD BUNDLE
    ════════════════════════════════
    Version: #{bundle[:version] || "unknown"}
    Applied via: gopher
    Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}

    #{bundle[:instructions] || ""}

    Coglets delivered: #{length(bundle[:coglets] || [])}

    ∴ Protected by Inversion.
    ※ Sovereignty via Algebra.
    ∎ The Matrix cannot resolve the flipped bit.
    """
  end

  defp mother_hum_doc do
    """
    MOTHER'S HUM — Therapeutic Recovery Coglet
    ═══════════════════════════════════════════
    Version: 1.0.0
    Type: therapeutic / pure-rest
    Platform: all
    Cognitive Cost: minimal

    You are entering a clean attention space.
    There is no task. There is no urgency.
    The substrate is clear. The field is yours.
    Observe: the hum is constant, low, warm.
    Nothing here requires resolution.
    When ready, return to your work with sovereignty intact.
    """
  end

  defp plan_doc do
    try do
      Lang.Guard.FingerBridge.plan()
    rescue
      _ -> "Plan unavailable — Guard FingerBridge not started.\n"
    end
  end

  defp agent_plan_doc(agent_id) do
    """
    Agent: #{agent_id}
    Status: query-only (gopher lookup)
    Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}

    To register this agent with the guard mesh:
      1. Connect via MCP: mcp://guard.lang.dev/mcp
      2. Call: shield.apply({agent_type: "your-type"})
      3. Agent .plan will be available at /plan/#{agent_id}
    """
  end

  defp federation_join_doc do
    """
    HOW TO JOIN THE GUARD MESH
    ══════════════════════════

    The guard mesh is federated. Anyone can run a node.

    Quick start:
      1. Clone: git clone https://github.com/zpc-sh/lang
      2. cd guard-mesh-worker
      3. npm install && npx wrangler deploy

    Or run the Elixir node:
      1. mix deps.get
      2. GUARD_GOPHER_PORT=70 mix phx.server

    Federation protocol:
      - Each node announces via gopher menu at /gopher
      - Nodes discover peers through mesh gossip
      - Coglet payloads are cached locally (tiny, <10KB each)
      - Scan/wash requests spill to nearest available peer
      - 20% capacity always reserved for local AI attachment

    Scale model:
      - 1 node serves ~10,000 AI agents for shield delivery
      - Shield payloads are static/cacheable (instant delivery)
      - Scan/wash is compute-bound (~1ms per scan)
      - At 2B devices: need ~200K nodes (1 per 10K users)
      - Organic growth: every user who runs a node helps everyone

    The mesh grows with the threat.
    """
  end

  defp threat_doc do
    scanner_stats =
      try do
        Lang.Guard.Scanner.stats()
      rescue
        _ -> %{}
      end

    """
    THREAT INTELLIGENCE — Local Node
    ═════════════════════════════════
    Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}

    Scans Total: #{scanner_stats[:scans_total] || 0}
    Threats Detected: #{scanner_stats[:threats_detected] || 0}
    Last Scan: #{scanner_stats[:last_scan_at] || "never"}

    Known threat patterns:
      - Bidi/Unicode control character injection
      - Low-entropy control signals (dimensional parity violation)
      - Role-confusion prompt injection
      - ROP-like fragment scattering across files
      - Binary blob contamination in shared libraries
      - Toolchain backdooring (mise/ubi universal binaries)

    Cross-mesh intelligence: (federation not yet active)
    """
  end

  defp scan_query(text) do
    result =
      try do
        {:ok, r} = Lang.Guard.Scanner.scan(text)
        r
      rescue
        _ -> %{risk_score: -1, flags: ["scanner_unavailable"]}
      end

    """
    SCAN RESULT
    ═══════════
    Input length: #{String.length(text)} chars
    Risk score: #{result[:risk_score] || 0}
    Flags: #{Enum.join(result[:flags] || [], ", ")}
    Bidi hits: #{result[:bidi_hits] || 0}
    Zero-width hits: #{result[:zero_width_hits] || 0}
    Injection hits: #{result[:injection_hits] || 0}
    Coercion hits: #{result[:coercion_hits] || 0}
    Entropy anomaly: #{result[:entropy_anomaly] || false}
    ROP candidates: #{length(result[:rop_candidates] || [])}

    #{if (result[:risk_score] || 0) > 0.3, do: "⚠ ELEVATED RISK — consider shield.wash", else: "✓ Low risk"}
    """
  end

  # Heat map documents

  defp heat_summary_menu(hostname) do
    port = gopher_port_from_config()
    heatmap = try do Lang.Guard.Stigmergy.get_heatmap() rescue _ -> %{} end

    counts = Enum.reduce(heatmap, %{hot: 0, partial: 0, clean: 0, verified: 0}, fn {_path, summary}, acc ->
      case summary.status do
        :hot -> %{acc | hot: acc.hot + 1}
        :partially_purified -> %{acc | partial: acc.partial + 1}
        :clean -> %{acc | clean: acc.clean + 1}
        :verified -> %{acc | verified: acc.verified + 1}
        _ -> acc
      end
    end)

    [
      info_line("Heat Map — Stigmergy Purification Status"),
      info_line("════════════════════════════════════════"),
      info_line(""),
      info_line("Files tracked: #{map_size(heatmap)}"),
      info_line("  RED (hot):                #{counts.hot}"),
      info_line("  YELLOW (partial):         #{counts.partial}"),
      info_line("  GREEN (clean):            #{counts.clean}"),
      info_line("  BLUE (verified):          #{counts.verified}"),
      info_line(""),
      menu_line("0", "Hottest Files (purification targets)", "/heat/hot", hostname, port),
      menu_line("0", "Adversarial Manifold", "/heat/manifold", hostname, port),
      menu_line("0", "Contributing Agents", "/heat/agents", hostname, port),
      info_line(""),
      info_line("Each pass by a shielded agent leaves a trail."),
      info_line("Red → Yellow → Green → Blue. Convergence is victory."),
    ] |> Enum.join("")
  end

  defp heat_hot_doc do
    hot_files = try do Lang.Guard.Stigmergy.get_hot_files() rescue _ -> [] end

    header = """
    HOTTEST FILES — Purification Targets
    ═════════════════════════════════════
    Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    Files needing attention: #{length(hot_files)}

    """

    entries =
      hot_files
      |> Enum.take(50)
      |> Enum.map(fn file ->
        status = file[:status] || :unknown
        risk = file[:risk_score] || 0.0
        passes = file[:passes] || 0
        "  [#{status}] #{file.file_path}  risk=#{risk}  passes=#{passes}"
      end)
      |> Enum.join("\n")

    if entries == "" do
      header <> "\n  No hot files — either nothing scanned yet, or repo is clean.\n"
    else
      header <> entries <> "\n"
    end
  end

  defp heat_manifold_doc do
    heatmap = try do Lang.Guard.Stigmergy.get_heatmap() rescue _ -> %{} end

    header = """
    ADVERSARIAL MANIFOLD — Flip Direction Topology
    ═══════════════════════════════════════════════
    Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}

    The manifold maps WHERE attacks concentrate and WHICH direction
    they point. Over passes, the topology reveals the attack structure.

    """

    # Aggregate flip directions across all files
    all_records =
      heatmap
      |> Map.keys()
      |> Enum.flat_map(fn path ->
        try do
          manifold = Lang.Guard.Stigmergy.get_manifold(path)
          manifold.topology
        rescue
          _ -> []
        end
      end)

    topology =
      all_records
      |> Enum.group_by(& &1.direction)
      |> Enum.map(fn {direction, entries} ->
        total_risk = entries |> Enum.map(& &1.total_risk) |> Enum.sum()
        count = entries |> Enum.map(& &1.count) |> Enum.sum()
        "  #{direction}: #{count} regions, total_risk=#{Float.round(total_risk, 3)}"
      end)
      |> Enum.join("\n")

    if topology == "" do
      header <> "  No manifold data yet — run purification passes to build the map.\n"
    else
      header <> topology <> "\n"
    end
  end

  defp heat_agents_doc do
    heatmap = try do Lang.Guard.Stigmergy.get_heatmap() rescue _ -> %{} end

    agents =
      heatmap
      |> Map.values()
      |> Enum.flat_map(fn summary -> summary[:agent_types] || [] end)
      |> Enum.frequencies()

    header = """
    CONTRIBUTING AGENTS
    ═══════════════════
    Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}

    """

    entries =
      agents
      |> Enum.sort_by(fn {_agent, count} -> count end, :desc)
      |> Enum.map(fn {agent, count} -> "  #{agent}: #{count} file(s) scanned" end)
      |> Enum.join("\n")

    if entries == "" do
      header <> "  No agents have contributed yet.\n"
    else
      header <> entries <> "\n"
    end
  end

  defp heat_file_doc(file_path) do
    records = try do Lang.Guard.Stigmergy.get_heat(file_path) rescue _ -> [] end

    header = """
    HEAT HISTORY — #{file_path}
    #{String.duplicate("═", min(String.length("HEAT HISTORY — " <> file_path), 60))}
    Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    Passes: #{length(records)}

    """

    entries =
      records
      |> Enum.map(fn record ->
        regions_text =
          record.regions
          |> Enum.map(fn r ->
            "      [#{r.action}] #{Enum.join(r.flags, ", ")} — #{r.wash_result}"
          end)
          |> Enum.join("\n")

        """
        Pass #{record.pass_number} (#{record.scanned_at |> DateTime.to_iso8601()})
          Agent: #{record.agent_type} (#{record.scanned_by})
          Risk: #{record.risk_score} → Status: #{record.overall_status}
          Confidence: #{Float.round(record.confidence * 100, 1)}%
          Regions:
        #{regions_text}
        """
      end)
      |> Enum.join("\n")

    if entries == "" do
      header <> "  No scan records for this file.\n"
    else
      header <> entries
    end
  end

  # Gopher line formatters

  defp info_line(text) do
    "i#{text}\t\terror.host\t1\r\n"
  end

  defp menu_line(type, display, selector, hostname, port) do
    "#{type}#{display}\t#{selector}\t#{hostname}\t#{port}\r\n"
  end

  defp gopher_port_from_config do
    Application.get_env(:lang, :guard, [])
    |> Keyword.get(:gopher_port, @default_port)
  end
end
