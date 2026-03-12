defmodule Lang.LSP.SpatialSuccessTest do
  use Lang.DataCase

  alias Lang.Analyses.Project
  alias Lang.Spatial.Map, as: SpatialMap

  setup do
    user = Lang.Factory.create_user!()
    {:ok, project} = Project.create(%{name: "Proj #{System.unique_integer()}", user_id: user.id})

    graph = %{
      symbols: %{
        "a.ex" => [
          %{kind: :function, name: "a1", line: 1, language: "elixir"}
        ],
        "b.ts" => [
          %{kind: :function, name: "b1", line: 1, language: "typescript"}
        ]
      },
      relations: [
        %{type: :import, from: "a.ex", to: "b.ts", language: "elixir", target_kind: :path}
      ]
    }

    stats = %{generated_at: DateTime.utc_now()}
    {:ok, _map} = SpatialMap.create(%{project_id: project.id, graph_summary: graph, stats: stats})
    {:ok, project_id: project.id}
  end

  test "traverse returns nodes, edges, and symbols with kinds", %{project_id: project_id} do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 100,
      "method" => "lang.spatial.traverse",
      "params" => %{
        "project_id" => project_id,
        "file" => "a.ex",
        "depth" => 1,
        "language" => "elixir",
        "types" => "import",
        "kinds" => "function"
      }
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"result" => result} = resp
    assert is_list(result["nodes"]) or is_list(result[:nodes])
    assert is_list(result["edges"]) or is_list(result[:edges])
  end

  test "traverse types normalization (imports) expands across import edges", %{
    project_id: project_id
  } do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 101,
      "method" => "lang.spatial.traverse",
      "params" => %{
        "project_id" => project_id,
        "file" => "a.ex",
        "depth" => 1,
        "language" => "elixir",
        "types" => "imports"
      }
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"result" => result} = resp
    nodes = (result["nodes"] || result[:nodes]) |> Enum.map(&(&1["file"] || &1[:file]))
    assert "b.ts" in nodes or "b.ex" in nodes
  end

  test "traverse kinds normalization (Function) returns symbols", %{project_id: project_id} do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 102,
      "method" => "lang.spatial.traverse",
      "params" => %{
        "project_id" => project_id,
        "file" => "a.ex",
        "depth" => 1,
        "language" => "elixir",
        "kinds" => "Function"
      }
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"result" => result} = resp
    symbols = result["symbols"] || %{}
    assert Map.has_key?(symbols, "a.ex")
  end
end
