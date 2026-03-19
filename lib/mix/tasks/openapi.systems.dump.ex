defmodule Mix.Tasks.Openapi.Systems.Dump do
  use Mix.Task
  @shortdoc "Print Systems OpenAPI spec path and endpoint counts"
  @moduledoc """
  Loads the generated Systems OpenAPI spec and prints useful info.

  Usage:
    mix openapi.systems.dump
  """

  @impl true
  def run(_args) do
    path = "priv/static/docs/systems/openapi.json"
    if File.exists?(path) do
      spec = File.read!(path) |> Jason.decode!()
      endpoints = spec["paths"] |> Map.keys() |> length()
      schemas = get_in(spec, ["components", "schemas"]) |> case do
        nil -> 0
        m when is_map(m) -> map_size(m)
        _ -> 0
      end
      Mix.shell().info("Systems OpenAPI: #{path}\nendpoints=#{endpoints} schemas=#{schemas}")
    else
      Mix.shell().error("Spec not found: #{path}. Enqueue with `mix openapi.systems`.")
    end
  end
end

