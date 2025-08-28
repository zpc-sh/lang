defmodule Lang.LSP.DispatchTest do
  use ExUnit.Case, async: false
  use Lang.DataCase

  alias Lang.LSP.Dispatch
  alias Lang.Think.Request, as: ThinkRequest
  alias Lang.Generate.Request, as: GenRequest
  alias Lang.Analysis
  alias Lang.Accounts.User
  alias Lang.Repo
  alias Oban.Job
  require Ash.Query

  setup do
    {:ok, user} = User.create(%{email: "lsp@test.local", name: "LSP User", organization_name: "LSP Org"})
    {:ok, project} = Analysis.create_project(%{name: "LSP Project", user_id: user.id})
    {:ok, user: user, project: project}
  end

  test "explain_intent enqueues think request", %{user: user, project: project} do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "lang.think.explain_intent",
      "params" => %{input: %{code: "def x, do: :ok"}, user_id: user.id, project_id: project.id}
    }

    resp = Dispatch.process(msg)
    assert %{"result" => %{"status" => "queued", "request_id" => req_id}} = resp

    {:ok, req} = ThinkRequest.by_id(req_id)
    assert req.kind == :explain_intent

    jobs = Repo.all(Job)
    assert Enum.any?(jobs, &(&1.worker == "Lang.Think.Workers.RequestWorker"))
  end

  test "complete_partial enqueues generate request", %{user: user, project: project} do
    msg = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "lang.generate.complete_partial",
      "params" => %{inputs: %{path: "README.md"}, user_id: user.id, project_id: project.id}
    }

    resp = Dispatch.process(msg)
    assert %{"result" => %{"status" => "queued", "request_id" => req_id}} = resp

    {:ok, req} = GenRequest.by_id(req_id)
    assert req.strategy == :complete_partial

    jobs = Repo.all(Job)
    assert Enum.any?(jobs, &(&1.worker == "Lang.Generate.Workers.RequestWorker"))
  end

  test "spatial.map enqueues map build", %{project: project} do
    msg = %{"jsonrpc" => "2.0", "id" => 3, "method" => "lang.spatial.map", "params" => %{project_id: project.id}}
    resp = Dispatch.process(msg)
    assert %{"result" => %{"enqueued" => true}} = resp

    jobs = Repo.all(Job)
    assert Enum.any?(jobs, &(&1.worker == "Lang.Spatial.Workers.MapBuilderWorker"))
  end
end

