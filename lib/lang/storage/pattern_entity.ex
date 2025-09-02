defmodule Lang.Storage.PatternEntity do
  @moduledoc """
  Ash ETS-backed resource for storing agent patterns locally.

  This serves as a local fallback when external storage (Folder) is disabled.
  """

  use Ash.Resource,
    domain: Lang.Storage,
    data_layer: Ash.DataLayer.Ets

  # Needed for query filter pins (^)
  require Ash.Query

  ets do
    private?(false)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :content, :map do
      allow_nil?(false)
      default(%{})
      description("Pattern content payload")
    end

    attribute :confidence, :decimal do
      allow_nil?(false)
      default(Decimal.new("0.5"))
      constraints(min: 0.0, max: 1.0)
      description("Confidence score between 0.0 and 1.0")
    end

    attribute :tags, {:array, :string} do
      allow_nil?(false)
      default([])
      description("Optional tags for filtering/search")
    end

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :store do
      accept([:content, :confidence, :tags])
    end

    update :update_confidence do
      require_atomic?(false)
      argument(:confidence, :decimal, allow_nil?: false)

      change(fn changeset, _ctx ->
        conf = Ash.Changeset.get_argument(changeset, :confidence)

        clamped =
          conf
          |> Decimal.max(Decimal.new("0.0"))
          |> Decimal.min(Decimal.new("1.0"))

        Ash.Changeset.change_attribute(changeset, :confidence, clamped)
      end)
    end
  end

  # Wrapper helpers (Ash v3 explicit)
  def store(attrs) when is_map(attrs) do
    __MODULE__
    |> Ash.Changeset.for_create(:store, attrs)
    |> Ash.create()
  end

  def get_many(ids) when is_list(ids) do
    __MODULE__
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read()
  end

  def get(id) when is_binary(id) do
    __MODULE__
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one()
  end

  def update_confidence(id, conf) when is_binary(id) do
    with {:ok, rec} when not is_nil(rec) <- get(id) do
      rec
      |> Ash.Changeset.for_update(:update_confidence, %{confidence: conf})
      |> Ash.update()
    end
  end
end
