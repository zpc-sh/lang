defmodule Lang.Ash.RedisDataLayer do
  @moduledoc """
  Minimal Redis-backed Ash DataLayer for ephemeral JSON records.

  - Keys are namespaced by resource module and id: e.g. "lang:workspace:state:<id>"
  - Values are JSON blobs; TTL configurable via `:ttl` attribute (seconds).
  - Supports basic equality filtering on primary key `id`.
  """

  # Note: Minimal custom DataLayer; we don't declare @behaviour to avoid noisy callback warnings.

  alias Ash.{Changeset, Query}

  def can?(_resource, action) when action in [:read, :create, :update, :destroy], do: true
  def can?(_resource, _), do: false

  def resource_to_query(resource, _api), do: {:ok, %Query{resource: resource}}

  def run_query(%Query{resource: resource, filter: filter}, _api) do
    with {:ok, key} <- key_from_filter(resource, filter),
         {:ok, json} <- Lang.Redis.get(key) do
      case json do
        nil -> {:ok, []}
        _ -> {:ok, [decode(resource, json)]}
      end
    else
      _ -> {:ok, []}
    end
  end

  def run_aggregate(_query, _aggregates, _api), do: {:ok, %{}}

  def run_calculation(_calc, _records, _api), do: {:ok, []}

  def run_action(%Changeset{} = changeset, _api) do
    case Changeset.action_type(changeset) do
      :create -> create(changeset)
      :update -> update(changeset)
      :destroy -> destroy(changeset)
    end
  end

  defp create(%Changeset{resource: resource} = changeset) do
    attrs = Changeset.get_attributes(changeset)
    id = attrs[:id] || attrs["id"]
    key = key_for(resource, id)

    with {:ok, json} <- Jason.encode(attrs),
         {:ok, _} <- Lang.Redis.setex(key, ttl(attrs), json) do
      {:ok, struct(resource, attrs)}
    end
  end

  defp update(%Changeset{resource: resource, data: data} = changeset) do
    attrs = Changeset.get_attributes(changeset)
    merged = Map.merge(Map.from_struct(data), attrs)
    id = merged[:id] || merged["id"]
    key = key_for(resource, id)

    with {:ok, json} <- Jason.encode(merged),
         {:ok, _} <- Lang.Redis.setex(key, ttl(merged), json) do
      {:ok, struct(resource, merged)}
    end
  end

  defp destroy(%Changeset{resource: resource, data: %{id: id}}) when is_binary(id) do
    _ = Lang.Redis.cmd(["DEL", key_for(resource, id)])
    {:ok, :ok}
  end

  defp destroy(changeset), do: {:ok, changeset.data}

  # Helpers
  defp key_from_filter(_resource, nil), do: {:error, :no_filter}
  defp key_from_filter(resource, %Ash.Filter{expression: expr}), do: key_from_expr(resource, expr)

  # Supports filter id == ^id
  defp key_from_expr(resource, {:==, _, [{{:., _, [{:&, _, [0]}, :id]}, _, _}, id]}),
    do: {:ok, key_for(resource, id)}

  defp key_from_expr(resource, {:and, _, [left, _right]}), do: key_from_expr(resource, left)
  defp key_from_expr(_resource, _), do: {:error, :unsupported_filter}

  defp key_for(resource, id) when is_binary(id), do: prefix(resource) <> id
  defp key_for(resource, id) when is_atom(id), do: key_for(resource, Atom.to_string(id))
  defp key_for(resource, id), do: key_for(resource, to_string(id))

  defp prefix(resource) do
    parts = Module.split(resource) |> Enum.map(&Macro.underscore/1)
    Enum.join(parts, ":") <> ":"
  end

  defp ttl(attrs), do: Map.get(attrs, :ttl, 7_200)

  defp decode(resource, json), do: struct(resource, Jason.decode!(json))
end
