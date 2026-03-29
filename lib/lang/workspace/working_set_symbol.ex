defmodule Lang.Workspace.WorkingSetSymbol do
  @moduledoc """
  Join module for the many-to-many relationship between WorkingSet and Symbol.
  """
  use Ash.Resource,
    domain: Lang.Workspaces,
    data_layer: Lang.Ash.RedisDataLayer

  attributes do
    uuid_primary_key(:id)

    attribute :working_set_id, :uuid

    attribute :symbol_id, :uuid

    # When this symbol was added to the working set
    attribute :added_at, :utc_datetime_usec do
      default(&DateTime.utc_now/0)
    end

    # Reason or context for adding the symbol
    attribute(:context, :string)
  end

  relationships do
    belongs_to :working_set, Lang.Workspace.WorkingSet do
      primary_key?(true)
    end

    belongs_to :symbol, Lang.Workspace.Symbol do
      primary_key?(true)
    end
  end

  identities do
    identity(:unique_working_set_symbol, [:working_set_id, :symbol_id])
  end

  actions do
    defaults([:create, :read, :destroy])
  end

  # Redis configuration
  # Match working_set TTL - 2 hours
  attributes do
    attribute(:ttl, :integer, default: 7200)
  end

  identities do
    identity(:by_working_set, [:working_set_id])
    identity(:by_symbol, [:symbol_id])
  end
end
