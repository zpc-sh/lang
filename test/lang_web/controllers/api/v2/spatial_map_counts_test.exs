defmodule LangWeb.Api.V2.SpatialMapCountsTest do
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

  test "counts_only languages scope and type/kind counts", %{conn: conn, project_id: project_id} do
    conn =
      get(conn, ~p"/api/v2/spatial/map/#{project_id}", %{counts_only: "true", languages: "elixir"})

    body = json_response(conn, 200)

    sym_meta = body["meta"]["symbols"]
    rel_meta = body["meta"]["relations"]

    assert sym_meta["counts_all_by_language"]["elixir"] == 2
    assert sym_meta["counts_by_language"]["elixir"] == 2
    assert sym_meta["counts_all_by_kind"]["function"] == 1
    assert sym_meta["counts_by_kind"]["function"] == 1

    assert rel_meta["counts_all_by_language"]["elixir"] == 2
    assert rel_meta["counts_by_language"]["elixir"] == 2
    # only elixir relations included; types present: import, use
    assert rel_meta["counts_all_by_type"]["import"] == 1
    assert rel_meta["counts_all_by_type"]["use"] == 1
  end

  test "relation types filter (imports)", %{conn: conn, project_id: project_id} do
    conn =
      get(conn, ~p"/api/v2/spatial/map/#{project_id}", %{
        section: "relations",
        counts_only: "true",
        types: "imports"
      })

    body = json_response(conn, 200)
    rel_meta = body["meta"]["relations"]
    # Only import should be counted in filtered set
    assert rel_meta["counts_by_type"]["import"] == 1
    assert Map.get(rel_meta["counts_by_type"], "use") in [nil, 0]
  end

  test "unknown types and kinds are ignored safely", %{conn: conn, project_id: project_id} do
    conn =
      get(conn, ~p"/api/v2/spatial/map/#{project_id}", %{
        section: "relations",
        counts_only: "true",
        types: "__foo__"
      })

    body = json_response(conn, 200)
    rel_meta = body["meta"]["relations"]
    # No known types in filter, so filtered set is empty
    assert rel_meta["counts_by_type"] == %{}

    conn2 =
      get(conn, ~p"/api/v2/spatial/map/#{project_id}", %{
        section: "symbols",
        counts_only: "true",
        kinds: "__bar__"
      })

    body2 = json_response(conn2, 200)
    sym_meta = body2["meta"]["symbols"]
    assert sym_meta["counts_by_kind"] == %{}
  end

  test "symbol kinds filter (function)", %{conn: conn, project_id: project_id} do
    conn =
      get(conn, ~p"/api/v2/spatial/map/#{project_id}", %{
        section: "symbols",
        counts_only: "true",
        kinds: "function"
      })

    body = json_response(conn, 200)
    sym_meta = body["meta"]["symbols"]
    assert sym_meta["counts_by_kind"]["function"] == 2
    assert Map.get(sym_meta["counts_by_kind"], "module") in [nil, 0]
  end

  test "combined filters: languages+types+kinds scope counts", %{
    conn: conn,
    project_id: project_id
  } do
    params = %{
      section: "all",
      counts_only: "true",
      languages: "elixir",
      types: "import",
      kinds: "function"
    }

    conn = get(conn, ~p"/api/v2/spatial/map/#{project_id}", params)
    body = json_response(conn, 200)

    sym_meta = body["meta"]["symbols"]
    rel_meta = body["meta"]["relations"]

    # Symbols: only elixir and kind=function (one function in a.ex)
    assert sym_meta["counts_by_language"]["elixir"] == 1
    assert sym_meta["counts_by_kind"]["function"] == 1

    # Relations: only elixir import (one relation)
    assert rel_meta["counts_by_language"]["elixir"] == 1
    assert rel_meta["counts_by_type"]["import"] == 1
    assert Map.get(rel_meta["counts_by_type"], "use") in [nil, 0]
  end
end
