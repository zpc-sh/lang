defmodule Lang.Tokens do
  @moduledoc """
  Ash domain for Token Optimization requests and results.

  Provides intelligent token management for AI operations including:
  - Token estimation across different model tokenizers
  - Context compression while preserving semantic meaning
  - Relevance-based filtering to reduce token usage
  - Delta streaming to minimize redundant tokens
  - Smart caching strategies based on usage patterns
  """

  use Ash.Domain

  resources do
    resource(Lang.Tokens.Request)
    resource(Lang.Tokens.Result)
  end
end
