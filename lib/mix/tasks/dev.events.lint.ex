
defmodule Mix.Tasks.Dev.Events.Lint do
  use Mix.Task
  @shortdoc "Lint event types used in code against the TypeRegistry"

  @moduledoc """
  Scans the codebase for `Lang.Events.track_event(%{event_type: "..."})` usages and
  compares them against `Lang.Events.TypeRegistry`.

      mix dev.events.lint
      mix dev.events.lint --fail

  Options:
    --fail  Exit with non-zero status if unknown events are found
  """

  @switches [fail: :boolean]

  def run(args) do
    {opts, _argv, _} = OptionParser.parse(args, switches: @switches)

    files = Path.wildcard("lib/**/*.ex") ++ Path.wildcard("lib/**/*.exs")
    # event_type: "string"
    rx_string = ~r/Lang\.Events\.track_event\(\%\{[^}]*event_type:\s*"([^"]+)"/m
    # event_type: :atom
    rx_atom = ~r/Lang\.Events\.track_event\(\%\{[^}]*event_type:\s*:(\w+)/m
    # "event_type" => "string"
    rx_string_key = ~r/Lang\.Events\.track_event\(\%\{[^}]*"event_type"\s*=>\s*"([^"]+)"/m
    # "event_type" => :atom
    rx_atom_key = ~r/Lang\.Events\.track_event\(\%\{[^}]*"event_type"\s*=>\s*:(\w+)/m

    types =
      Enum.flat_map(files, fn path ->
        case File.read(path) do
          {:ok, content} ->
            (for [_, t] <- Regex.scan(rx_string, content), do: {path, t}) ++
            (for [_, t] <- Regex.scan(rx_atom, content), do: {path, t}) ++
            (for [_, t] <- Regex.scan(rx_string_key, content), do: {path, t}) ++
            (for [_, t] <- Regex.scan(rx_atom_key, content), do: {path, t})
          _ -> []
        end
      end)

    unknown =
      types
      |> Enum.map(fn {p, t} -> {p, t, Lang.Events.TypeRegistry.resolve(t)} end)
      |> Enum.filter(fn {_p, _t, res} -> res == :unknown end)

    if unknown == [] do
      Mix.shell().info("✅ All event types are known")
      :ok
    else
      Mix.shell().info("⚠️  Unknown event types:")
      Enum.each(unknown, fn {p, t, _} -> Mix.shell().info("  #{t}  (#{p})") end)
      if opts[:fail], do: Mix.raise("unknown event types found"), else: :ok
    end
  end
end
