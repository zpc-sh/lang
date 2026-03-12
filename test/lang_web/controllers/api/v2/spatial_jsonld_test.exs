defmodule LangWeb.Api.V2.SpatialJSONLDTest do
  use LangWeb.ConnCase, async: true
  use Lang.DataCase

  alias Lang.Analyses.Project
  alias Lang.Spatial.Map, as: SpatialMap

  @ctx "https://lang.nulity.com/context/spatial"

  setup %{conn: conn} do
    user = Lang.Factory.create_user!()
    {:ok, project} = Project.create(%{name: "Proj #{System.unique_integer()}", user_id: user.id})

    graph = %{
      symbols: %{
        "a.ex" => [%{kind: :function, name: "a1", line: 1, language: "elixir"}],
        "b.ex" => [%{kind: :function, name: "b1", line: 1, language: "elixir"}]
      },
      relations: [
        %{type: :import, from: "a.ex", to: "b.ex", language: "elixir", target_kind: :path}
      ]
    }

    stats = %{generated_at: DateTime.utc_now()}
    {:ok, _map} = SpatialMap.create(%{project_id: project.id, graph_summary: graph, stats: stats})

    conn =
      conn
      |> Plug.Conn.assign(:current_user, user)
      |> Plug.Conn.put_req_header("accept", "application/ld+json")

    {:ok, conn: conn, project_id: project.id}
  end

  test "trace_path returns @context when JSON-LD negotiated", %{
    conn: conn,
    project_id: project_id
  } do
    conn = get(conn, ~p"/api/v2/spatial/trace_path/#{project_id}", %{from: "a.ex", to: "b.ex"})
    body = json_response(conn, 200)
    assert body["@context"] == @ctx
  end

  test "map_summary returns @context when JSON-LD negotiated", %{
    conn: conn,
    project_id: project_id
  } do
    conn = get(conn, ~p"/api/v2/spatial/map/#{project_id}")
    body = json_response(conn, 200)
    assert body["@context"] == @ctx
  end
end
