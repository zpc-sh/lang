defmodule Lang.LSP.SpatialPathRelatedSuccessTest do
  use Lang.DataCase

  alias Lang.Analyses.Project
  alias Lang.Spatial.Map, as: SpatialMap

  setup do
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
    {:ok, project_id: project.id}
  end

  test "trace_path LSP returns path", %{project_id: project_id} do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 123,
      "method" => "lang.spatial.trace_path",
      "params" => %{
        "project_id" => project_id,
        "from" => "a.ex",
        "to" => "c.ex",
        "language" => "elixir"
      }
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"result" => result} = resp
    assert result["from"] == "a.ex"
    assert result["to"] == "c.ex"
  end

  test "find_related LSP returns related", %{project_id: project_id} do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 124,
      "method" => "lang.spatial.find_related",
      "params" => %{"project_id" => project_id, "file" => "a.ex", "language" => "elixir"}
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"result" => result} = resp
    assert result["file"] == "a.ex"
    assert is_list(result["related"]) or is_list(result[:related])
  end

  test "trace_path LSP honors types filter (use only yields not_found)", %{project_id: project_id} do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 125,
      "method" => "lang.spatial.trace_path",
      "params" => %{
        "project_id" => project_id,
        "from" => "a.ex",
        "to" => "c.ex",
        "language" => "elixir",
        "types" => "use"
      }
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"result" => result} = resp
    assert result["not_found"] == true
  end

  test "find_related LSP honors types filter (import only returns [])", %{project_id: project_id} do
    # With types=use only, from a.ex has no neighbors; related should be empty
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 126,
      "method" => "lang.spatial.find_related",
      "params" => %{
        "project_id" => project_id,
        "file" => "a.ex",
        "language" => "elixir",
        "types" => "use"
      }
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"result" => result} = resp
    assert result["related"] in [[], nil]
  end
end
