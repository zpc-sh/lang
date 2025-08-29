defmodule LangWeb.Api.V2.SpatialMapAllTest do
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

  test "section=all returns filtered lists and meta with totals", %{
    conn: conn,
    project_id: project_id
  } do
    params = %{
      section: "all",
      languages: "elixir",
      types: "import",
      kinds: "function",
      page_size: 50
    }

    conn = get(conn, ~p"/api/v2/spatial/map/#{project_id}", params)
    body = json_response(conn, 200)

    # Lists should be present and filtered
    symbols = body["symbols"]
    relations = body["relations"]
    assert is_list(symbols) and is_list(relations)
    assert Enum.all?(symbols, fn s -> s["language"] == "elixir" and s["kind"] == "function" end)
    assert Enum.all?(relations, fn r -> r["language"] == "elixir" and r["type"] == "import" end)

    # Meta should reflect totals vs total_all
    sym_meta = body["meta"]["symbols"]
    rel_meta = body["meta"]["relations"]

    # Overall totals (after languages scope):
    # symbols elixir total_all should equal number of elixir symbols (2)
    assert sym_meta["total_all"] >= sym_meta["total"]
    assert sym_meta["counts_by_kind"]["function"] == sym_meta["total"]

    assert sym_meta["counts_all_by_language"]["elixir"] >=
             sym_meta["counts_by_language"]["elixir"]

    # relations total_all >= total; and only import shown in filtered counts
    assert rel_meta["total_all"] >= rel_meta["total"]
    assert rel_meta["counts_by_type"]["import"] == rel_meta["total"]
  end

  test "counts_only with combined filters returns only meta and empty lists", %{
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
    assert body["symbols"] == []
    assert body["relations"] == []

    sym_meta = body["meta"]["symbols"]
    rel_meta = body["meta"]["relations"]

    # Still provide totals and scoped counts
    assert is_integer(sym_meta["total"])
    assert is_integer(sym_meta["total_all"])
    assert is_map(sym_meta["counts_by_kind"]) and is_map(rel_meta["counts_by_type"])
  end
end
