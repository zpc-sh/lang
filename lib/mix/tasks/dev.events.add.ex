
defmodule Mix.Tasks.Dev.Events.Add do
  use Mix.Task
  @shortdoc "Add an event type to the registry override (config/events.exs)"

  @moduledoc """
  Adds an event type to `config/events.exs` under the `:lang, :events` extra mappings.

      mix dev.events.add my_event --category api_usage
      mix dev.events.add my_prefix_ --category user_activity --prefix

  Options:
    --category  One of: user_activity | api_usage | performance | billing (required)
    --prefix    Treat the argument as a prefix instead of an exact event type
  """

  @switches [category: :string, prefix: :boolean]

  def run(args) do
    {opts, [name | _], _} = OptionParser.parse(args, strict: @switches)
    unless name do
      Mix.raise("usage: mix dev.events.add <event_type_or_prefix> --category <category> [--prefix]")
    end

    cat = parse_category(opts[:category])
    is_prefix = opts[:prefix] || false

    file = Path.join(["config", "events.exs"]) |> Path.expand()
    ensure_import()

    # Load current config if present
    extra =
      case File.exists?(file) do
        true ->
          try do
            import Config
            {_, _} = Code.eval_file(file)
            Application.get_env(:lang, :events, [])[:extra] || %{exact: %{}, prefixes: %{}}
          rescue
            _ -> %{exact: %{}, prefixes: %{}}
          end
        false -> %{exact: %{}, prefixes: %{}}
      end

    extra =
      if is_prefix do
        put_in(extra, [:prefixes, name], cat)
      else
        put_in(extra, [:exact, name], cat)
      end

    # Write back the events.exs file with only the extra section (registry merges it at runtime)
    content = render(extra)
    file
    |> Path.dirname()
    |> File.mkdir_p()
    |> case do
      :ok -> :ok
      {:error, reason} -> Mix.raise("failed to create directory for #{file}: #{inspect(reason)}")
    end

    File.write!(file, content)
    Mix.shell().info("Updated #{file} with #{if is_prefix, do: "prefix", else: "event"} '#{name}' => #{cat}")
  end

  defp parse_category("user_activity"), do: :user_activity
  defp parse_category("api_usage"), do: :api_usage
  defp parse_category("performance"), do: :performance
  defp parse_category("billing"), do: :billing
  defp parse_category(other), do: Mix.raise("unknown category: #{inspect(other)}")

  defp render(%{exact: exact, prefixes: prefixes}) do
    exact_kv =
      Enum.map(exact, fn {k, v} ->
        ~s(\n      "#{k}" => :#{v})
      end)
      |> Enum.join(",")

    prefixes_kv =
      Enum.map(prefixes, fn {k, v} ->
        ~s(\n      "#{k}" => :#{v})
      end)
      |> Enum.join(",")
    """
    import Config

    config :lang, :events,
      extra: %{
        exact: %{
#{exact_kv}
    },
        prefixes: %{
#{prefixes_kv}
    }
      }
    """
  end

  defp ensure_import do
    cfg = Path.join(["config", "config.exs"]) |> Path.expand()
    if File.exists?(cfg) do
      body = File.read!(cfg)
      unless String.contains?(body, ~s(import_config "events.exs")) do
        File.write!(cfg, body <> "\nimport_config \"events.exs\"\n")
        Mix.shell().info(~s(Appended import_config "events.exs" to config/config.exs))
      end
    end
  end
end
