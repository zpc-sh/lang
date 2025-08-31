defmodule Mix.Tasks.Dev.Db.Down do
  @shortdoc "Stop Postgres + Redis (keep volumes)"
  @moduledoc @shortdoc
  use Mix.Task

  def run(_args) do
    DevTasksHelper.docker_compose!(["down"])
  end
end

