defmodule Lang.Lsp.MetricEvent do
  @moduledoc """
  An Ash resource for storing LSP metric events.
  """
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [Ash.Resource.Dsl, Ash.Extensions.Time]

  postgres do
    table "lsp_metric_events"
    repo Lang.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :method, :string do
      description "The LSP method that was called."
      allow_nil? false
    end

    attribute :latency_ms, :integer do
      description "The duration of the request in milliseconds."
      allow_nil? false
    end

    attribute :user_id, :uuid do
      description "The ID of the user who made the request."
      allow_nil? true
    end

    attribute :organization_id, :uuid do
      description "The ID of the organization for the request."
      allow_nil? true
    end

    attribute :project_id, :string do
      description "Identifier for the project context."
      allow_nil? true
    end

    attribute :session_id, :string do
      description "Identifier for the LSP session."
      allow_nil? true
    end

    attribute :client_info, :map do
      description "Information about the client that made the request."
      allow_nil? true
    end

    create_timestamp(:created_at)
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end
end
