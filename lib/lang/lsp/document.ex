defmodule Lang.LSP.Document do
  @moduledoc """
  Persistent representation of LSP documents (by URI) with content, version,
  language id, and opened state. Publishes PubSub notifications (AshEvents-style)
  so UIs and tools can react to open/change/close.
  """

  use Ash.Resource,
    otp_app: :lang,
    domain: Lang.LSP,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "lsp_documents"
    repo Lang.Repo
  end

  pub_sub do
    prefix("lsp:documents")
    module(LangWeb.Endpoint)

    transform(fn doc ->
      %{
        uri: doc.uri,
        language_id: doc.language_id,
        version: doc.version,
        opened: doc.opened,
        client_id: doc.client_id,
        root_uri: doc.root_uri,
        updated_at: Map.get(doc, :updated_at)
      }
    end)

    publish(:open, "global")
    publish(:open, [:uri])
    publish(:update_content, [:uri])
    publish(:close, [:uri])
  end

  attributes do
    uuid_primary_key :id

    attribute :uri, :string do
      allow_nil? false
      public? true
    end

    attribute :language_id, :string do
      allow_nil? true
      public? true
    end

    attribute :version, :integer do
      default 0
      public? true
    end

    # Use :string; DB can map to TEXT
    attribute :content, :string do
      allow_nil? true
      sensitive? true
      public? true
    end

    attribute :opened, :boolean do
      default true
      public? true
    end

    attribute :client_id, :string do
      allow_nil? true
      public? true
    end

    attribute :root_uri, :string do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_uri, [:uri]
  end

  actions do
    defaults [:read]

    create :open do
      accept [:uri, :language_id, :version, :content, :client_id, :root_uri, :opened]
      upsert? true
      upsert_identity :unique_uri
      change fn changeset, _ ->
        # Ensure opened true on open unless explicitly provided
        case Ash.Changeset.get_attribute(changeset, :opened) do
          nil -> Ash.Changeset.change_attribute(changeset, :opened, true)
          _ -> changeset
        end
      end
    end

    update :update_content do
      accept [:language_id, :version, :content, :client_id]
      change fn changeset, _ ->
        # Keep document marked as opened on content update
        Ash.Changeset.change_attribute(changeset, :opened, true)
      end
    end

    update :close do
      accept []
      change fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :opened, false)
      end
    end

    read :open_docs do
      filter expr(opened == true)
      prepare build(limit: 200, sort: [updated_at: :desc])
    end
  end

  code_interface do
    define :open
    define :update_content
    define :close
    define :open_docs, action: :open_docs
    define :by_uri, get_by: [:uri], action: :read
  end
end

