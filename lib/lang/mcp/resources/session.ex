defmodule Lang.MCP.Resources.Session do
  @moduledoc """
  Minimal Ash resource placeholder for MCP sessions.
  This satisfies relationships from Connection until full session
  modeling is implemented.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: nil

  postgres do
    table("mcp_sessions")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute :metadata, :map, default: %{}
    timestamps()
  end
end

