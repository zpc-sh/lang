defmodule Lang.Spatial do
  @moduledoc """
  Ash domain for spatial code navigation (maps, waypoints, paths).
  """

  use Ash.Domain
  require Ash.Query

  resources do
    resource(Lang.Spatial.Map)
    resource(Lang.Spatial.Waypoint)
    resource(Lang.Spatial.Path)
  end

  @doc """
  Ensure a map snapshot is enqueued/built for a project.

  Delegates work to Oban worker. Prefer using resource actions for data ops.
  """
  @spec ensure_map(String.t(), keyword()) :: {:ok, any()} | {:error, term()}
  def ensure_map(project_id, opts \\ []) when is_binary(project_id) do
    args = %{"project_id" => project_id}
    args = if path = Keyword.get(opts, :path), do: Map.put(args, "path", path), else: args
    job = Lang.Spatial.Workers.MapBuilderWorker.new(args, queue: :analysis)
    Oban.insert(job)
  end

  @doc """
  Read latest spatial map for a project.
  """
  @spec latest_map(String.t()) :: {:ok, map() | struct() | nil} | {:error, term()}
  def latest_map(project_id) when is_binary(project_id) do
    if Code.ensure_loaded?(Lang.Spatial.Map) do
      Lang.Spatial.Map
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read_one()
    else
      {:ok, nil}
    end
  end

  @doc """
  Return a normalized flattened summary of latest map.
  """
  @spec latest_map_summary(String.t()) :: {:ok, map() | nil} | {:error, term()}
  def latest_map_summary(project_id) do
    case latest_map(project_id) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, map} when is_map(map) or is_struct(map) ->
        gs = Map.get(map, :graph_summary) || %{}

        {:ok,
         %{
           map_id: Map.get(map, :id),
           project_id: Map.get(map, :project_id),
           generated_at: fetch_in(Map.get(map, :stats) || %{}, ["generated_at", :generated_at]),
           stats: Map.get(map, :stats) || %{},
           symbols: normalize_symbols(gs),
           relations: normalize_relations(gs)
         }}

      other ->
        other
    end
  end

  # Normalization helpers
  defp normalize_symbols(graph_summary) when is_map(graph_summary) do
    symbols = fetch_in(graph_summary, ["symbols", :symbols]) || %{}

    symbols
    |> Enum.flat_map(fn {file, entries} ->
      Enum.map(entries || [], fn e ->
        %{
          file: file,
          kind: fetch_in(e, ["kind", :kind]),
          name: fetch_in(e, ["name", :name]),
          line: fetch_in(e, ["line", :line]),
          language: fetch_in(e, ["language", :language]),
          ts: fetch_in(e, ["ts", :ts]) || false
        }
      end)
    end)
  end

  defp normalize_symbols(_), do: []

  defp normalize_relations(graph_summary) when is_map(graph_summary) do
    rels = fetch_in(graph_summary, ["relations", :relations]) || []

    Enum.map(rels, fn r ->
      %{
        type: fetch_in(r, ["type", :type]),
        from: fetch_in(r, ["from", :from]),
        to: fetch_in(r, ["to", :to]),
        line: fetch_in(r, ["line", :line]),
        language: fetch_in(r, ["language", :language]),
        target_kind: fetch_in(r, ["target_kind", :target_kind]),
        ts: fetch_in(r, ["ts", :ts]) || false
      }
    end)
  end

  defp normalize_relations(_), do: []

  defp fetch_in(map, [k1, k2]) when is_map(map), do: Map.get(map, k1) || Map.get(map, k2)
  defp fetch_in(map, [k]) when is_map(map), do: Map.get(map, k)
end
