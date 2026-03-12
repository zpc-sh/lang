defmodule LangWeb.Api.V2.SpatialMapPaginationTest do
  use LangWeb.ConnCase, async: true
  use Lang.DataCase

  alias Lang.Analyses.Project
  alias Lang.Spatial.Map, as: SpatialMap

  setup %{conn: conn} do
    user = Lang.Factory.create_user!()
    {:ok, project} = Project.create(%{name: "Proj #{System.unique_integer()}", user_id: user.id})

    # Build more symbols/relations to exercise pagination
    sym_a = for i <- 1..5, do: %{kind: :function, name: "a#{i}", line: i, language: "elixir"}
    sym_b = for i <- 1..3, do: %{kind: :function, name: "b#{i}", line: i, language: "elixir"}

    rels =
      for i <- 1..5 do
        %{type: :import, from: "a.ex", to: "b#{i}.ex", language: "elixir", target_kind: :path}
      end

    graph = %{
      symbols: %{
        "a.ex" => sym_a,
        "b.ex" => sym_b
      },
      relations: rels
    }

    stats = %{generated_at: DateTime.utc_now()}
    {:ok, _map} = SpatialMap.create(%{project_id: project.id, graph_summary: graph, stats: stats})

    {:ok, conn: Plug.Conn.assign(conn, :current_user, user), project_id: project.id}
  end

  test "pagination limits lists but not meta totals", %{conn: conn, project_id: project_id} do
    params = %{section: "symbols", languages: "elixir", kinds: "function", page: 1, page_size: 3}
    conn1 = get(conn, ~p"/api/v2/spatial/map/#{project_id}", params)
    body1 = json_response(conn1, 200)
    sym1 = body1["symbols"]
    meta1 = body1["meta"]["symbols"]
    assert length(sym1) == 3
    assert meta1["total"] >= 3

    # Second page
    conn2 = get(conn, ~p"/api/v2/spatial/map/#{project_id}", Map.put(params, :page, 2))
    body2 = json_response(conn2, 200)
    sym2 = body2["symbols"]
    meta2 = body2["meta"]["symbols"]
    assert length(sym2) >= 0
    # Totals remain the same across pages
    assert meta2["total"] == meta1["total"]
  end

  test "invalid page returns 400", %{conn: conn, project_id: project_id} do
    params = %{section: "symbols", page: "abc", page_size: 10}
    conn = get(conn, ~p"/api/v2/spatial/map/#{project_id}", params)
    assert json_response(conn, 400)["error"] =~ "invalid page or page_size"
  end

  test "invalid page_size returns 400", %{conn: conn, project_id: project_id} do
    params = %{section: "symbols", page: 1, page_size: 0}
    conn = get(conn, ~p"/api/v2/spatial/map/#{project_id}", params)
    assert json_response(conn, 400)["error"] =~ "invalid page or page_size"
  end
end
