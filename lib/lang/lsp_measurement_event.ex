defmodule Lang.LspMeasurementEvent do
  @moduledoc """
  Represents an LSP measurement event for logging and analysis.

  Emits PubSub notifications (AshEvents-style) on create for real-time dashboards.
  """
  use Ash.Resource,
    domain: Lang.LspDomain,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "lsp_measurement_events"
    repo Lang.Repo
  end

  # PubSub notifications for real-time monitoring
  pub_sub do
    # Topics like: "lsp:measurements:global", "lsp:measurements:client_id", "lsp:measurements:method"
    prefix("lsp:measurements")
    module(LangWeb.Endpoint)

    transform(fn ev ->
      %{
        id: ev.id,
        client_id: ev.client_id,
        method: ev.method,
        duration_ms: ev.duration_ms,
        at: ev.created_at
      }
    end)

    publish(:create, "global")
    publish(:create, [:client_id])
    publish(:create, [:method])
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

    attribute :provider, :string do
      allow_nil? true
      description "AI provider involved, if any (e.g., openai, anthropic)."
    end

    attribute :model, :string do
      allow_nil? true
      description "Model name used by provider, if any."
    end

    attribute :tokens_in, :integer do
      allow_nil? true
      description "Estimated/request tokens in (optional)."
    end

    attribute :tokens_out, :integer do
      allow_nil? true
      description "Estimated/response tokens out (optional)."
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

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
  end
end
