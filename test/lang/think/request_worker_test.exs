defmodule Lang.Think.RequestWorkerTest do
  use ExUnit.Case, async: false
  use Lang.DataCase

  alias Lang.Think.{Request, Result}
  alias Lang.Think.Workers.RequestWorker
  alias Lang.Analysis
  alias Lang.Accounts.User

  @moduletag :integration

  test "think worker completes request and writes result" do
    {:ok, user} =
      User.create(%{
        email: "think@test.local",
        name: "Think User",
        organization_name: "Think Org"
      })

    {:ok, project} = Analysis.create_project(%{name: "Think Project", user_id: user.id})

    {:ok, req} =
      Request.create(%{
        kind: :explain_intent,
        input: %{code: "def x, do: :ok"},
        user_id: user.id,
        project_id: project.id
      })

    assert :ok = RequestWorker.perform(%Oban.Job{args: %{"request_id" => req.id}})

    {:ok, req_after} = Request.by_id(req.id)
    assert req_after.status == :completed

    {:ok, res} =
      Result
      |> Ash.Query.filter(request_id == ^req.id)
      |> Ash.read_one()

    assert res != nil
    assert is_map(res.details)
  end
end
