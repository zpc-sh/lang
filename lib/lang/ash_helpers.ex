defmodule Lang.AshHelpers do
  @moduledoc """
  Small helpers for common Ash patterns.

  Use these to keep organization scoping and setting consistent
  across services and resource interactions.
  """

  import Ash.Query

  @doc """
  Scope a queryable to an organization id.
  """
  def scope_to_org(queryable, org_id) when is_binary(org_id) do
    filter(queryable, organization_id == ^org_id)
  end

  @doc """
  Set organization_id on a changeset.
  """
  def set_org(changeset, org_id) when is_binary(org_id) do
    Ash.Changeset.change_attribute(changeset, :organization_id, org_id)
  end
end
