defmodule Lang.AST.Snapshot do
  @moduledoc """
  Compact AST snapshot stored in ETS by Lang.AST.Store.

  This is intentionally lightweight; the `tree` field may hold a
  parser-native representation (e.g., a tree-sitter handle or a
  compact JSON-like map) depending on your backend.
  """

  @enforce_keys [:uri, :version, :lang, :text_hash, :root]
  defstruct [
    # string
    :uri,
    # integer (LSP version)
    :version,
    # string/language id
    :lang,
    # sha256 or similar
    :text_hash,
    # compact root node map or parser ref
    :root,
    # optional precomputed symbols
    symbols: [],
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
