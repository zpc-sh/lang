defmodule Lang.LspMeasurementEvent do
  @moduledoc """
  Represents an LSP measurement event for logging and analysis.
  """
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshEvents]

  postgres do
    table "lsp_measurement_events"
    repo Lang.Repo
  end

  events do
    domain Lang.LspDomain
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end

  attributes do
    uuid_primary_key :id

    attribute :client_id, :string do
      allow_nil? false
      description "The ID of the LSP client that initiated the event."
    end

    attribute :method, :string do
      allow_nil? false
      description "The LSP method that was called."
    end

    attribute :request, :map do
      allow_nil? false
      description "The request payload."
    end

    attribute :response, :map do
      allow_nil? true
      description "The response payload."
    end

    attribute :duration_ms, :integer do
      allow_nil? true
      description "The duration of the LSP method call in milliseconds."
    end

    attribute :error, :string do
      allow_nil? true
      description "Any error message associated with the LSP method call."
    end

    create_timestamp :created_at
  end

  relationships do
    # If there are other resources that relate to LSP events, define them here.
  end
end