defmodule Lang.AST.Snapshot do
  @moduledoc """
  Compact AST snapshot stored in ETS by Lang.AST.Store.

  This is intentionally lightweight; the `tree` field may hold a
  parser-native representation (e.g., a tree-sitter handle or a
  compact JSON-like map) depending on your backend.
  """

  @enforce_keys [:uri, :version, :lang, :text_hash, :root]
  defstruct [
    :uri,          # string
    :version,      # integer (LSP version)
    :lang,         # string/language id
    :text_hash,    # sha256 or similar
    :root,         # compact root node map or parser ref
    symbols: [],   # optional precomputed symbols
    diagnostics: [],
    meta: %{}
  ]

  @type t :: %__MODULE__{
          uri: String.t(),
          version: non_neg_integer(),
          lang: String.t(),
          text_hash: String.t(),
          root: any(),
          symbols: list(),
          diagnostics: list(),
          meta: map()
        }
end

