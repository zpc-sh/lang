defmodule Mix.Tasks.Dev.Db.Wipe do
  @shortdoc "Stop and remove volumes (DANGEROUS)"
  @moduledoc @shortdoc
  use Mix.Task

  def run(_args) do
    DevTasksHelper.docker_compose!(["down", "-v"])
  end
end

