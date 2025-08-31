defmodule Lang.Dev.ModelRegistry do
  @moduledoc """
  Dev-only model registry (Ash ETS) to track JSON‑LD models and rendered status.
  """

  use Ash.Resource,
    domain: Lang.Dev,
    data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
    write_concurrency?(true)
    read_concurrency?(true)
  end

  attributes do
    attribute :model_id, :string, allow_nil?: false
    attribute :version, :string, allow_nil?: false, default: "0.1.0"
    attribute :hash, :string, allow_nil?: false
    attribute :path, :string, allow_nil?: false
    attribute :rendered_at, :utc_datetime_usec
    attribute :status, :string, allow_nil?: true, default: "draft"
    attribute :status_changed_at, :utc_datetime_usec
    attribute :changed_by, :string, allow_nil?: true
    attribute :owner, :string, allow_nil?: true
    attribute :notes, :string, allow_nil?: true
  end

  identities do
    identity :unique_model, [:model_id]
  end

  actions do
    defaults [:read]

    create :upsert do
      upsert? true
      upsert_identity :unique_model
      accept [:model_id, :version, :hash, :path, :rendered_at, :status, :status_changed_at, :changed_by, :owner, :notes]
      primary? true
    end

    update :touch do
      accept [:version, :hash, :rendered_at, :path, :status, :status_changed_at, :changed_by, :owner, :notes]
      primary? true
    end
  end
end
