defmodule Lang.Generate.RequestWorkerTest do
  use ExUnit.Case, async: false
  use Lang.DataCase

  alias Lang.Generate.{Request, Artifact}
  alias Lang.Generate.Workers.RequestWorker
  alias Lang.Analysis
  alias Lang.Accounts.User

  @moduledag :integration

  test "generate worker emits artifacts" do
    {:ok, user} = User.create(%{email: "gen@test.local", name: "Gen User", organization_name: "Gen Org"})
    {:ok, project} = Analysis.create_project(%{name: "Gen Project", user_id: user.id})
    {:ok, req} = Request.create(%{strategy: :complete_partial, inputs: %{path: "README.md"}, boundaries: %{}, user_id: user.id, project_id: project.id})

    assert :ok = RequestWorker.perform(%Oban.Job{args: %{"request_id" => req.id}})

    {:ok, req_after} = Request.by_id(req.id)
    assert req_after.status == :completed

    {:ok, artifacts} =
      Artifact
      |> Ash.Query.filter(request_id == ^req.id)
      |> Ash.read()

    assert length(artifacts) >= 1
  end
end

