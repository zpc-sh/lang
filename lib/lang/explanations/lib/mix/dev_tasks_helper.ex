defmodule DevTasksHelper do
  @moduledoc false

  def ensure_executable!(exe) do
    case System.find_executable(exe) do
      nil ->
        Mix.raise("Required executable not found: #{exe}. Please install it and ensure it's on PATH.")

      path ->
        path
    end
  end

  def run_cmd!(cmd, args, opts \\ []) do
    default = [into: IO.stream(:stdio, :line)]
    {_, status} = System.cmd(cmd, args, Keyword.merge(default, opts))
    if status != 0, do: Mix.raise("Command failed: #{cmd} #{Enum.join(args, " ")}")
    :ok
  end

  def docker_compose!(args) when is_list(args) do
    ensure_executable!("docker")
    run_cmd!("docker", ["compose" | args])
  end

  def env(var, default), do: System.get_env(var) || default
end

