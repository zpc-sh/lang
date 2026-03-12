defmodule Lang.Spatial.MapBuilderWorkerTest do
  use ExUnit.Case, async: false
  use Lang.DataCase

  alias Lang.Spatial.{Map}
  alias Lang.Spatial.Workers.MapBuilderWorker
  alias Lang.Analysis
  alias Lang.Accounts.User

  @moduletag :integration

  test "map builder creates snapshot with fs stats when path provided" do
    {:ok, user} =
      User.create(%{
        email: "spatial@test.local",
        name: "Spatial User",
        organization_name: "Spatial Org"
      })

    {:ok, project} = Analysis.create_project(%{name: "Spatial Project", user_id: user.id})

    tmp = System.tmp_dir!() |> Path.join("spatial_map_test")
    File.mkdir_p!(tmp)
    File.write!(Path.join(tmp, "a.ex"), "defmodule A do end\n")
    File.write!(Path.join(tmp, "b.js"), "function b() {}\n")

    assert :ok =
             MapBuilderWorker.perform(%Oban.Job{
               args: %{"project_id" => project.id, "path" => tmp}
             })

    {:ok, map} =
      Map
      |> Ash.Query.filter(project_id == ^project.id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read_one()

    assert map != nil
    assert is_map(map.stats)
  end
end
