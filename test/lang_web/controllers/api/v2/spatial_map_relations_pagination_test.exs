defmodule LangWeb.Api.V2.SpatialMapRelationsPaginationTest do
  use LangWeb.ConnCase, async: true
  use Lang.DataCase

  alias Lang.Analyses.Project
  alias Lang.Spatial.Map, as: SpatialMap

  setup %{conn: conn} do
    user = Lang.Factory.create_user!()
    {:ok, project} = Project.create(%{name: "Proj #{System.unique_integer()}", user_id: user.id})

    rels =
      for i <- 1..10 do
        %{type: :import, from: "a#{i}.ex", to: "b#{i}.ex", language: "elixir", target_kind: :path}
      end

    graph = %{
      symbols: %{},
      relations: rels
    }

    stats = %{generated_at: DateTime.utc_now()}
    {:ok, _map} = SpatialMap.create(%{project_id: project.id, graph_summary: graph, stats: stats})

    {:ok, conn: Plug.Conn.assign(conn, :current_user, user), project_id: project.id}
  end

  test "relations pagination limits lists; totals stable", %{conn: conn, project_id: project_id} do
    params = %{section: "relations", languages: "elixir", types: "import", page: 1, page_size: 4}
    conn1 = get(conn, ~p"/api/v2/spatial/map/#{project_id}", params)
    body1 = json_response(conn1, 200)
    rels1 = body1["relations"]
    meta1 = body1["meta"]["relations"]
    assert length(rels1) == 4
    assert meta1["total"] >= 4

    conn2 = get(conn, ~p"/api/v2/spatial/map/#{project_id}", Map.put(params, :page, 3))
    body2 = json_response(conn2, 200)
    rels2 = body2["relations"]
    meta2 = body2["meta"]["relations"]
    # last page may be shorter
    assert length(rels2) <= 4
    assert meta2["total"] == meta1["total"]
  end
end

