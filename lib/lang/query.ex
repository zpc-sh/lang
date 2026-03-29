defmodule Lang.Query do
  @moduledoc """
  Ash domain for Natural Language Query requests and results.

  Provides intelligent natural language querying capabilities for codebases:
  - Natural language code queries and semantic search
  - Impact analysis ("What breaks if I change X?")
  - Dependency analysis ("What depends on this?")
  - Code ownership tracking ("Who owns this code?")

  This domain integrates with existing providers, graph reasoning, and
  dependency analysis capabilities to provide comprehensive query functionality.
  """

  use Ash.Domain

  resources do
    resource(Lang.Query.Request)
    resource(Lang.Query.Result)
  end
end
