defmodule Lang.LSP.DomainGraph do
  @moduledoc """
  Adjacency graph for LSP method domains used to "foveate" exposure.

  We use this to proactively pre-warm adjacent domains when a new domain
  is first used by a client, without blocking or exposing everything.
  """

  @type domain :: :core | :doc_io | :completion | :code_nav | :lang_custom | :generative

  @adj %{
    core: [:doc_io, :completion],
    doc_io: [:completion, :code_nav],
    completion: [:doc_io, :code_nav],
    code_nav: [:doc_io, :completion],
    lang_custom: [:core],
    # Generative functions are unrelated and expensive; never prewarm implicitly
    generative: []
  }

  @doc """
  Returns adjacent domains for a given domain (unique, deterministic order).
  """
  @spec adjacent(domain()) :: [domain()]
  def adjacent(domain) do
    Map.get(@adj, domain, [])
  end
end
