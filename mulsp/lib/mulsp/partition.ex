defmodule Mulsp.Partition do
  @moduledoc """
  Dynamic partition config. Each mulsp instance gets a custom kit-out.
  No two mulsp are the same — a security specialist gets dc + guard,
  a code reviewer gets lsp + proxy, a coordinator gets mesh + dc.

  Config can come from:
  - Compiled defaults (this module)
  - Environment variables
  - Pushed at runtime via gopher/dispatch
  - Inherited from the birthing Lang SaaS
  """

  defstruct [
    :node_id,
    local_methods: [],
    proxy_methods: %{},
    mesh_methods: [],
    lang_methods: [],
    # Protocol ports (0 = pick random available)
    gopher_port: 7070,
    finger_port: 7079,
    dc_port: 7071,
    lsp_port: 7080,
    # Control port — Lang pushes partition updates here (localhost only)
    control_port: 7100,
    # Feature toggles
    dc_enabled: true,
    finger_enabled: true,
    lsp_enabled: true,
    # Guard level: :minimal | :standard | :paranoid
    # Minimal = inline UTF-8 + size check only (cheap)
    # Heavy scanning is Niyuta's domain
    guard_level: :minimal,
    # List of enabled protocols
    protocols: [:gopher, :finger],
    # Lang platform bridge address (if proxying)
    lang_host: nil,
    lang_port: nil,
    # Distributed Erlang cookie for clustering
    cookie: nil,
    # Peer seeds for initial mesh discovery
    peer_seeds: []
  ]

  @doc """
  Load partition config. For now, defaults.
  The Lang SaaS will push custom configs when birthing mulsp serverlets.
  """
  def load do
    node_id = generate_node_id()

    %__MODULE__{
      node_id: node_id,
      local_methods: [
        "initialize", "initialized", "shutdown", "exit",
        "textDocument/didOpen", "textDocument/didChange", "textDocument/didClose"
      ],
      proxy_methods: %{},
      mesh_methods: [
        "lang.think.*", "lang.spatial.*", "lang.agent.*"
      ],
      lang_methods: [
        "lang.workspace.*", "lang.graph.*", "lang.cloud.*"
      ],
      cookie: generate_cookie(),
      control_port: env_int("MULSP_CONTROL_PORT", 7100)
    }
  end

  defp env_int(var, default) do
    case System.get_env(var) do
      nil -> default
      val -> String.to_integer(val)
    end
  end

  defp generate_node_id do
    # 8 bytes of entropy, hex-encoded
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
    |> then(&"mulsp-#{&1}")
  rescue
    # AtomVM may not have :crypto — fall back to timestamp
    _ -> "mulsp-#{System.system_time(:millisecond)}"
  end

  defp generate_cookie do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  rescue
    _ -> "mulsp-#{System.system_time(:millisecond)}"
  end
end
