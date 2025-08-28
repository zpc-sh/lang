defmodule LangWeb.Api.V2.SpatialControllerSuccessTest do
  use LangWeb.ConnCase, async: true
  use Lang.DataCase

  alias Lang.Analyses.Project
  alias Lang.Spatial.Map, as: SpatialMap

  setup %{conn: conn} do
    user = Lang.Factory.create_user!()
    {:ok, project} = Project.create(%{name: "Proj #{System.unique_integer()}", user_id: user.id})

    graph = %{
      symbols: %{
        "a.ex" => [%{kind: :function, name: "a1", line: 1, language: "elixir"}],
        "b.ex" => [%{kind: :function, name: "b1", line: 1, language: "elixir"}],
        "c.ex" => [%{kind: :function, name: "c1", line: 1, language: "elixir"}]
      },
      relations: [
        %{type: :import, from: "a.ex", to: "b.ex", language: "elixir", target_kind: :path},
        %{type: :use, from: "b.ex", to: "c.ex", language: "elixir", target_kind: :path}
      ]
    }

    stats = %{generated_at: DateTime.utc_now()}
    {:ok, _map} = SpatialMap.create(%{project_id: project.id, graph_summary: graph, stats: stats})

    {:ok, conn: Plug.Conn.assign(conn, :current_user, user), project_id: project.id}
  end

  test "trace_path returns shortest path", %{conn: conn, project_id: project_id} do
    conn = get(conn, ~p"/api/v2/spatial/trace_path/#{project_id}", %{from: "a.ex", to: "c.ex", language: "elixir"})
    body = json_response(conn, 200)
    assert body["from"] == "a.ex"
    assert body["to"] == "c.ex"
    # nodes and edges should be present
    assert is_list(body["nodes"]) or is_list(body[:nodes])
    assert is_list(body["edges"]) or is_list(body[:edges])
  end

  test "find_related returns related nodes", %{conn: conn, project_id: project_id} do
    conn = get(conn, ~p"/api/v2/spatial/find_related/#{project_id}", %{file: "a.ex", language: "elixir"})
    body = json_response(conn, 200)
    assert body["file"] == "a.ex"
    assert is_list(body["related"]) or is_list(body[:related])
  end

  test "traverse returns symbols when kinds provided", %{conn: conn, project_id: project_id} do
    conn = get(conn, ~p"/api/v2/spatial/traverse/#{project_id}", %{file: "a.ex", depth: 2, language: "elixir", kinds: "function"})
    body = json_response(conn, 200)
    assert is_list(body["nodes"]) or is_list(body[:nodes])
    assert is_list(body["edges"]) or is_list(body[:edges])
    # symbols map should include a.ex with function entries
    symbols = body["symbols"] || %{}
    assert Map.has_key?(symbols, "a.ex")
    assert Enum.any?(symbols["a.ex"], fn s -> (s["kind"] || s[:kind]) in ["function", :function] end)
  end

  test "traverse honors types filter (use only)", %{conn: conn, project_id: project_id} do
    # From a.ex, only 'import' edge exists first; with types=use, graph should not expand
    conn = get(conn, ~p"/api/v2/spatial/traverse/#{project_id}", %{file: "a.ex", depth: 2, language: "elixir", types: "use"})
    body = json_response(conn, 200)
    nodes = body["nodes"] || []
    assert length(nodes) == 1
    assert (List.first(nodes)["file"] || List.first(nodes)[:file]) == "a.ex"
  end

  test "trace_path honors types filter (use only yields not_found)", %{conn: conn, project_id: project_id} do
    conn = get(conn, ~p"/api/v2/spatial/trace_path/#{project_id}", %{from: "a.ex", to: "c.ex", language: "elixir", types: "use"})
    body = json_response(conn, 200)
    assert body["not_found"] == true
  end
end
