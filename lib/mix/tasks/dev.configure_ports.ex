defmodule Mix.Tasks.Dev.ConfigurePorts do
  use Mix.Task
  @shortdoc "Auto-configure DB_PORT/PORT if defaults are taken"

  @moduledoc """
  Checks common dev ports and assigns free alternatives without starting servers.

  - Postgres: if 5432 is taken, choose a free port and set `DB_PORT`.
    Writes to `.env.local` and sets the current process env. Prints a
    docker run snippet you can use to start a local Postgres container
    bound to the chosen port.

  - Phoenix: checks 4000; if taken, assigns a free port to `PORT` and persists it.

  This task makes no network connections beyond checking local port bind,
  and it does not start long-running processes.
  """

  alias Nullity.CDFM.Adapters.FileAdapter.FSScanner, as: FileAdapter

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    pg_port = configure_postgres_port()
    web_port = configure_phoenix_port()

    Mix.shell().info("\nConfiguration complete:")
    Mix.shell().info("  DB_PORT=#{pg_port}")
    Mix.shell().info("  PORT=#{web_port}")

    :ok
  end

  defp configure_postgres_port do
    default = 5432
    chosen =
      if port_taken?(default) do
        pick_free_port([default])
      else
        default
      end

    persist_env(%{"DB_PORT" => Integer.to_string(chosen)})

    if chosen != default do
      Mix.shell().info("[postgres] 5432 is busy; selected free port #{chosen}")
      Mix.shell().info("[postgres] To start a local container bound to #{chosen}, run:")
      Mix.shell().info("  docker run --name lang-pg -e POSTGRES_PASSWORD=postgres -p #{chosen}:5432 -d postgres:15")
    else
      Mix.shell().info("[postgres] 5432 available; using default")
    end

    chosen
  end

  defp configure_phoenix_port do
    default = 4000
    chosen =
      if port_taken?(default) do
        pick_free_port([default])
      else
        default
      end

    persist_env(%{"PORT" => Integer.to_string(chosen)})

    if chosen != default do
      Mix.shell().info("[phoenix] 4000 is busy; selected free port #{chosen}")
    else
      Mix.shell().info("[phoenix] 4000 available; using default")
    end

    chosen
  end

  defp port_taken?(port) when is_integer(port) and port > 0 do
    case :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true]) do
      {:ok, sock} -> :gen_tcp.close(sock); false
      {:error, _} -> true
    end
  end

  defp pick_free_port(exclude) do
    # Search a few times in a safe range
    Stream.repeatedly(fn -> :rand.uniform(50_000) + 10_000 end)
    |> Stream.reject(&(&1 in exclude))
    |> Enum.find(fn p -> not port_taken?(p) end)
  end

  defp persist_env(kv) when is_map(kv) do
    # 1) Set process env for immediate use
    Enum.each(kv, fn {k, v} -> System.put_env(k, v) end)

    # 2) Update project .env.local for future sessions
    path = ".env.local"
    existing =
      case FileAdapter.read(path) do
        {:ok, bin} when is_binary(bin) -> bin
        _ -> ""
      end

    updated = upsert_env(existing, kv)
    case FileAdapter.write(path, updated) do
      :ok -> :ok
      {:error, reason} -> Mix.shell().error("Failed to write #{path}: #{inspect(reason)}")
    end
  end

  defp upsert_env(content, kv) when is_binary(content) and is_map(kv) do
    lines = String.split(content, "\n", trim: false)
    {acc, remaining} = Enum.map_reduce(lines, kv, fn line, rest ->
      case String.trim(line) do
        <<?#, _::binary>> -> {line, rest}
        <<>> -> {line, rest}
        _ ->
          case String.split(line, "=", parts: 2) do
            [k, _v] ->
              if Map.has_key?(rest, k) do
                {k <> "=" <> Map.fetch!(rest, k), Map.delete(rest, k)}
              else
                {line, rest}
              end
            _ -> {line, rest}
          end
      end
    end)

    # Append any remaining keys
    tail =
      remaining
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join("\n")

    Enum.join(acc, "\n") <> if(tail == "", do: "", else: (if(String.ends_with?(content, "\n"), do: "", else: "\n")) <> tail <> "\n")
  end
end
