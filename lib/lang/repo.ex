defmodule Lang.Repo do
  use AshPostgres.Repo, otp_app: :lang

  def installed_extensions do
    ["uuid-ossp", "citext", "ash-functions"]
  end

  def min_pg_version do
    %Version{major: 17, minor: 4, patch: 0}
  end

  @doc """
  Used by migrations --tenants to list all tenants, create related schemas, and migrate them.
  """
  @impl true
  def all_tenants do
    for tenant <- Ash.read!(Kyozo.Accounts.Team) do
      tenant.domain
    end
  end
end
