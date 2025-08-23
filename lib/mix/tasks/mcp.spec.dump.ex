defmodule Mix.Tasks.Mcp.Spec.Dump do
  use Mix.Task
  @shortdoc "Print MCP OpenAPI spec path and endpoint counts"
  @moduledoc """
  Loads the generated MCP OpenAPI spec and prints useful info.

  Usage:
    mix mcp.spec.dump
  """

  @impl true
  def run(_args) do
    spec_path = Path.expand("priv/static/docs/mcp/openapi.json")
    if File.exists?(spec_path) do
      {:ok, bin} = File.read(spec_path)
      spec = Jason.decode!(bin)
      paths = Map.get(spec, "paths", %{})
      IO.puts("Spec: #{spec_path}")
      IO.puts("Endpoints: #{map_size(paths)}")
      Enum.each(paths, fn {p, ops} ->
        methods = ops |> Map.keys() |> Enum.join(",")
        IO.puts(" - #{p} [#{methods}]")
      end)
    else
      Mix.shell().error("Spec not found at #{spec_path}. Run `mix mcp.spec` first.")
    end
  end
end

