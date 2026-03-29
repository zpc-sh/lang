defmodule Lang.Semantic.Insights.Insight do
  @moduledoc """
  Insight entity produced from JSON‑LD sources (e.g., AI Memory layers) or runtime generation.

  Embedded resource (no DB migration required) to allow immediate wiring. Can be moved to Postgres later.
  """

  use Ash.Resource, data_layer: Ash.DataLayer.Ets

  ets do
    private? true
    table :insights_ash_table
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :content, :string
    attribute :tags, {:array, :string}, default: []
    attribute :lang, :string, default: "en"
    attribute :source_uri, :string
    attribute :owner_id, :string
    attribute :workspace_id, :string
    attribute :layer_type, :string
    attribute :metadata, :map, default: %{}
    attribute :inserted_at, :utc_datetime_usec
    attribute :updated_at, :utc_datetime_usec
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
    end
  end
end
