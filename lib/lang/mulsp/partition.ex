defmodule Lang.Mulsp.Partition do
  @moduledoc """
  Context-sensitive partition builder for mulsp/muyata instances.

  Lang's 150+ LSP methods are carved across mulsp instances based on
  the AI context: what the AI is doing, what domain it's operating in,
  and what level of trust/guard is warranted.

  Each partition is the DNA that gets baked into a spawned BEAM child
  or emitted as part of an AtomVM packbeam `.avm`.
  """

  @type context :: :security | :code_review | :coordinator | :workspace | :generic
  @type guard_level :: :minimal | :standard | :paranoid

  @type t :: %{
    node_id: String.t() | nil,
    role: context(),
    local_methods: [String.t()],
    proxy_methods: %{String.t() => String.t()},
    mesh_methods: [String.t()],
    lang_methods: [String.t()],
    gopher_port: non_neg_integer(),
    finger_port: non_neg_integer(),
    dc_port: non_neg_integer(),
    lsp_port: non_neg_integer(),
    control_port: non_neg_integer(),
    dc_enabled: boolean(),
    finger_enabled: boolean(),
    lsp_enabled: boolean(),
    guard_level: guard_level(),
    protocols: [atom()],
    lang_host: String.t() | nil,
    lang_port: non_neg_integer() | nil,
    cookie: String.t() | nil,
    peer_seeds: [String.t()]
  }

  # Core LSP lifecycle — every partition gets these
  @lifecycle_methods ~w[
    initialize initialized shutdown exit
    textDocument/didOpen textDocument/didChange textDocument/didClose
  ]

  @doc """
  Build a partition for a given AI context.

  Contexts:
  - `:security` — guard-heavy, security scanning methods, paranoid mode
  - `:code_review` — explain/diff/traverse methods, LSP-forward
  - `:coordinator` — agent spawn/mesh coordination, no LSP
  - `:workspace` — workspace/graph/cloud methods, proxies heavy ops to Lang
  - `:generic` — balanced default for unknown context
  """
  def for_context(context, opts \\ []) do
    base = base_partition(opts)
    apply_context(base, context)
  end

  @doc "Serialize to ETF binary for wire transfer or packbeam injection."
  def to_etf(partition) do
    :erlang.term_to_binary(partition)
  end

  @doc "Deserialize from ETF."
  def from_etf(binary) when is_binary(binary) do
    :erlang.binary_to_term(binary)
  end

  @doc "Serialize to a key=value config string for AtomVM startup args."
  def to_atomvm_config(partition) do
    # AtomVM reads startup config from app priv or init args.
    # Encode as simple ETF — mulsp reads this via :init.get_arguments() or priv file.
    to_etf(partition)
  end

  # --- Private ---

  defp base_partition(opts) do
    lang_host = Keyword.get(opts, :lang_host, "127.0.0.1")
    lang_port = Keyword.get(opts, :lang_port, 4000)
    base_port = Keyword.get(opts, :base_port, 7080)

    %{
      node_id: nil,
      role: :generic,
      local_methods: @lifecycle_methods,
      proxy_methods: %{},
      mesh_methods: [],
      lang_methods: [],
      gopher_port: base_port,
      finger_port: base_port + 9,
      dc_port: base_port + 1,
      lsp_port: base_port + 10,
      control_port: base_port + 20,
      dc_enabled: true,
      finger_enabled: true,
      lsp_enabled: true,
      guard_level: :minimal,
      protocols: [:gopher, :finger],
      lang_host: lang_host,
      lang_port: lang_port,
      cookie: nil,
      peer_seeds: []
    }
  end

  defp apply_context(base, :security) do
    %{base |
      role: :security,
      local_methods: base.local_methods ++ ~w[
        lang.think.security_scan
        lang.agent.scan
        lang.guard.check
        lang.guard.entropy
        lang.guard.bidi_scan
      ],
      guard_level: :paranoid,
      dc_enabled: true,
      lsp_enabled: false,
      lang_methods: ~w[lang.cloud.* lang.graph.*],
      mesh_methods: ~w[lang.agent.*]
    }
  end

  defp apply_context(base, :code_review) do
    %{base |
      role: :code_review,
      local_methods: base.local_methods ++ ~w[
        lang.think.explain_code
        lang.think.explain_diff
        lang.spatial.traverse
        lang.spatial.locate
        lang.diff.*
      ],
      guard_level: :standard,
      lsp_enabled: true,
      lang_methods: ~w[lang.workspace.* lang.graph.*],
      mesh_methods: ~w[lang.agent.spawn lang.acg.*]
    }
  end

  defp apply_context(base, :coordinator) do
    %{base |
      role: :coordinator,
      local_methods: base.local_methods ++ ~w[
        lang.agent.spawn
        lang.agent.list
        lang.agent.kill
        lang.acg.route
        lang.acg.broadcast
      ],
      guard_level: :minimal,
      lsp_enabled: false,
      dc_enabled: true,
      lang_methods: ~w[lang.cloud.* lang.tokens.*],
      mesh_methods: ~w[lang.think.* lang.spatial.*]
    }
  end

  defp apply_context(base, :workspace) do
    %{base |
      role: :workspace,
      local_methods: base.local_methods ++ ~w[
        lang.workspace.open
        lang.workspace.close
        lang.workspace.list
        lang.graph.traverse
        lang.graph.query
      ],
      guard_level: :standard,
      lsp_enabled: true,
      lang_methods: ~w[lang.cloud.* lang.billing.*],
      mesh_methods: ~w[lang.agent.* lang.think.*]
    }
  end

  defp apply_context(base, :generic) do
    %{base |
      role: :generic,
      mesh_methods: ~w[lang.think.* lang.spatial.* lang.agent.*],
      lang_methods: ~w[lang.workspace.* lang.graph.* lang.cloud.*]
    }
  end
end
