defmodule Mix.Tasks.Dev.Db.Restart do
  @shortdoc "Restart db and redis services"
  @moduledoc @shortdoc
  use Mix.Task

  def run(_args) do
    # If a service doesn't exist, docker compose returns non-zero; ignore via two calls
    try do
      DevTasksHelper.docker_compose!(["restart", "db", "redis"]) 
    rescue
      _ -> DevTasksHelper.docker_compose!(["restart"]) 
    end
  end
end

