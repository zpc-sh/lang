defmodule LangWeb.Api.V2.SpatialMapListsTest do
  use LangWeb.ConnCase, async: true
  use Lang.DataCase

  alias Lang.Analyses.Project
  alias Lang.Spatial.Map, as: SpatialMap

  setup %{conn: conn} do
    user = Lang.Factory.create_user!()
    {:ok, project} = Project.create(%{name: "Proj #{System.unique_integer()}", user_id: user.id})

    graph = %{
      symbols: %{
        "a.ex" => [
          %{kind: :function, name: "a1", line: 1, language: "elixir"},
          %{kind: :module, name: "A", line: 0, language: "elixir"}
        ],
        "b.ts" => [
          %{kind: :function, name: "b1", line: 1, language: "typescript"}
        ]
      },
      relations: [
        %{type: :import, from: "a.ex", to: "b.ts", language: "elixir", target_kind: :path},
        %{type: :use, from: "a.ex", to: "A", language: "elixir", target_kind: :module},
        %{type: :export, from: "b.ts", to: "b1", language: "typescript", target_kind: :symbol}
      ]
    }

    stats = %{generated_at: DateTime.utc_now()}
    {:ok, _map} = SpatialMap.create(%{project_id: project.id, graph_summary: graph, stats: stats})

    {:ok, conn: Plug.Conn.assign(conn, :current_user, user), project_id: project.id}
  end

  test "symbols list respects languages + kinds", %{conn: conn, project_id: project_id} do
    params = %{section: "symbols", languages: "elixir", kinds: "function", page_size: 50}
    conn = get(conn, ~p"/api/v2/spatial/map/#{project_id}", params)
    body = json_response(conn, 200)
    symbols = body["symbols"]
    assert is_list(symbols)
    assert Enum.all?(symbols, fn s -> s["language"] == "elixir" and s["kind"] == "function" end)
  end

  test "relations list respects languages + types", %{conn: conn, project_id: project_id} do
    params = %{section: "relations", languages: "elixir", types: "import", page_size: 50}
    conn = get(conn, ~p"/api/v2/spatial/map/#{project_id}", params)
    body = json_response(conn, 200)
    rels = body["relations"]
    assert is_list(rels)
    assert Enum.all?(rels, fn r -> r["language"] == "elixir" and r["type"] == "import" end)
  end
end

