defmodule Lang.Dev.LSPTrace do
  @moduledoc """
  Dev-only LSP trace records (ring buffer approximated by limiting reads).

  Stores concise metadata and a small payload preview/digest.
  """

  use Ash.Resource,
    domain: Lang.Dev,
    data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  attributes do
    uuid_primary_key :id
    attribute :client_id, :string, allow_nil?: false
    attribute :dir, :string, allow_nil?: false # "rx" | "tx"
    attribute :method, :string, allow_nil?: true
    attribute :rpc_id, :string, allow_nil?: true
    attribute :status, :string, allow_nil?: true # ok|error
    attribute :duration_ms, :integer, allow_nil?: true
    attribute :payload_digest, :string, allow_nil?: true
    attribute :payload_preview, :string, allow_nil?: true
    attribute :error, :string, allow_nil?: true
    attribute :at, :utc_datetime_usec, allow_nil?: false, default: &DateTime.utc_now/0
  end

  actions do
    defaults [:read]

    create :log do
      primary? true
      accept [:client_id, :dir, :method, :rpc_id, :status, :duration_ms, :payload_digest, :payload_preview, :error, :at]
    end
  end
end

