defmodule Mix.Tasks.Spec.Rollout do
  use Mix.Task
  @shortdoc "Export spec tools/docs to multiple target repos"
  @moduledoc """
  Usage:
    mix spec.rollout --dest ../jsonld --dest ../markdown_ld
    mix spec.rollout --dests "../jsonld,../markdown_ld"

  Sources of destinations (in order):
  - Repeated --dest flags
  - --dests comma-separated list
  - SPEC_ROLLOUT_TARGETS env (comma-separated)
  - Fallback: ../jsonld and ../markdown_ld if they exist
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [dest: :keep, dests: :string])

    from_flags = Keyword.get_values(opts, :dest)
    from_list = opts |> Keyword.get(:dests) |> split_csv()
    from_env = System.get_env("SPEC_ROLLOUT_TARGETS") |> split_csv()

    fallbacks =
      ["../jsonld", "../markdown_ld"]
      |> Enum.filter(&File.dir?(&1))

    dests =
      (from_flags ++ from_list ++ from_env ++ fallbacks)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if dests == [] do
      Mix.raise("No destinations found. Pass --dest/--dests, set SPEC_ROLLOUT_TARGETS, or ensure ../jsonld and ../markdown_ld exist.")
    end

    failures =
      Enum.reduce(dests, 0, fn dest, acc ->
        Mix.shell().info("\n==> Rolling out to #{dest}")
        # Ensure nested tasks run for each destination within the same VM
        Mix.Task.reenable("spec.export.docs")
        Mix.Task.reenable("spec.export.tools")
        Mix.Task.run("spec.export.tools", ["--dest", dest])
        case verify(dest) do
          :ok -> acc
          {:error, missing} ->
            Mix.shell().error("Verification failed for #{dest}; missing: \n  - " <> Enum.join(missing, "\n  - "))
            acc + 1
        end
      end)

    Mix.shell().info("\nRollout complete for #{length(dests)} target(s)")
    if failures > 0, do: Mix.shell().error("#{failures} target(s) failed verification")
  end

  defp split_csv(nil), do: []
  defp split_csv(str), do: String.split(str, ",", trim: true)

  defp verify(dest) do
    checks = [
      "mix.exs",
      "AGENTS.codex.md",
      "lib/mix/tasks/spec.lint.ex",
      "lib/mix/tasks/spec.apply.ex",
      "lib/mix/tasks/spec.msg.new.ex",
      "lib/mix/tasks/spec.thread.render.ex",
      "work/spec_requests/README.receivers.md",
      "work/spec_requests/ack.schema.json",
      "work/spec_requests/message.schema.json"
    ]

    missing =
      checks
      |> Enum.map(&{&1, Path.join(dest, &1)})
      |> Enum.reject(fn {_rel, path} -> File.exists?(path) end)
      |> Enum.map(&elem(&1, 0))

    if missing == [], do: :ok, else: {:error, missing}
  end
end
