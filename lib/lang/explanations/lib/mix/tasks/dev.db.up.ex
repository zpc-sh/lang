defmodule Mix.Tasks.Dev.Db.Up do
  @shortdoc "Start Postgres + Redis via docker compose"
  @moduledoc @shortdoc
  use Mix.Task

  def run(_args) do
    DevTasksHelper.docker_compose!(["up", "-d"])
  end
end

