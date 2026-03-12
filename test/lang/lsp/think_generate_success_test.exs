defmodule Lang.LSP.ThinkGenerateSuccessTest do
  use Lang.DataCase

  alias Lang.Analyses.Project

  setup do
    user = Lang.Factory.create_user!()
    {:ok, project} = Project.create(%{name: "Proj #{System.unique_integer()}", user_id: user.id})
    {:ok, user_id: user.id, project_id: project.id}
  end

  test "think.explain_intent queues a request", %{user_id: user_id, project_id: project_id} do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 200,
      "method" => "lang.think.explain_intent",
      "params" => %{
        "input" => %{"code" => "def foo, do: :ok"},
        "user_id" => user_id,
        "project_id" => project_id
      }
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"result" => %{"request_id" => _id, "status" => "queued"}} = resp
  end

  test "generate.complete_partial queues a request", %{user_id: user_id, project_id: project_id} do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 201,
      "method" => "lang.generate.complete_partial",
      "params" => %{
        "inputs" => %{"snippet" => "def foo"},
        "boundaries" => %{},
        "user_id" => user_id,
        "project_id" => project_id
      }
    }

    resp = Lang.LSP.Dispatch.process(msg)
    assert %{"result" => %{"request_id" => _id, "status" => "queued"}} = resp
  end
end
