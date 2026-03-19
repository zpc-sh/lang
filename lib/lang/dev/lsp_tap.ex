defmodule Lang.Dev.LSPTap do
  @moduledoc """
  Dev-only LSP tap configuration per client.

  Stores whether capture is active, allowed methods, and max items.
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
    attribute :active, :boolean, allow_nil?: false, default: false
    attribute :methods, :string, allow_nil?: true, default: ""
    attribute :max, :integer, allow_nil?: false, default: 500
    attribute :updated_at, :utc_datetime_usec, allow_nil?: false, default: &DateTime.utc_now/0
  end

  actions do
    defaults [:read]

    create :put do
      accept [:client_id, :active, :methods, :max, :updated_at]
      primary? true
    end
  end

  code_interface do
    define :upsert, action: :put
  end
end

