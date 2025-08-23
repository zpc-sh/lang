defmodule Lang.MCP.Resources.Request do
  @moduledoc """
  Minimal Ash resource placeholder for MCP connection requests.
  Used for satisfying relationships; extend with actual schema later.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: nil

  postgres do
    table("mcp_requests")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute :method, :string
    attribute :params, :map, default: %{}
    attribute :result, :map, default: %{}
    timestamps()
  end

  relationships do
    belongs_to :connection, Lang.MCP.Resources.Connection do
      allow_nil?(false)
    end
  end
end

