defmodule Lang.Dev.ModelState do
  @moduledoc """
  Immutable history records for model pipeline states over time (dev‑only).

  Records snapshots on render/ingest and status changes with JSON‑LD snapshot, version, hash, etc.
  """

  use Ash.Resource,
    domain: Lang.Dev,
    data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  attributes do
    uuid_primary_key :id
    attribute :model_id, :string, allow_nil?: false
    attribute :version, :string, allow_nil?: false
    attribute :hash, :string, allow_nil?: false
    attribute :status, :string, allow_nil?: true
    attribute :path, :string, allow_nil?: true
    attribute :event_type, :string, allow_nil?: false
    attribute :actor, :string, allow_nil?: true
    attribute :snapshot, :map, allow_nil?: true, default: %{}
    attribute :at, :utc_datetime_usec, allow_nil?: false, default: &DateTime.utc_now/0
  end

  actions do
    defaults [:read]

    create :record do
      primary? true
      accept [:model_id, :version, :hash, :status, :path, :event_type, :actor, :snapshot, :at]
    end
  end
end

