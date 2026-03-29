defmodule Lang.Think.Result do
  @moduledoc """
  Output of a cognitive request (summary, details, artifacts, metrics).
  """

  use Ash.Resource,
    domain: Lang.Think,
    data_layer: AshPostgres.DataLayer

  alias Lang.Think.Request

  postgres do
    table("think_results")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :summary, :string do
      allow_nil?(true)
    end

    attribute :details, :map do
      allow_nil?(false)
      default(%{})
    end

    attribute :artifacts, {:array, :map} do
      allow_nil?(false)
      default([])
    end

    attribute :confidence_score, :decimal do
      allow_nil?(true)
    end

    attribute :metrics, :map do
      allow_nil?(false)
      default(%{})
    end

    attribute :completed_at, :utc_datetime do
      allow_nil?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :request, Request do
      attribute_writable?(true)
    end
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :request_id,
        :summary,
        :details,
        :artifacts,
        :confidence_score,
        :metrics,
        :completed_at
      ])
    end
  end

  code_interface do
    define(:read_all, action: :read)
    define(:by_id, action: :read, get_by: [:id])
    define(:create, action: :create)
  end
end
