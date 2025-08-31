defmodule Mix.Tasks.Dev.Db.Status do
  @shortdoc "Show docker compose service status"
  @moduledoc @shortdoc
  use Mix.Task

  def run(_args) do
    DevTasksHelper.docker_compose!(["ps"])
  end
end

