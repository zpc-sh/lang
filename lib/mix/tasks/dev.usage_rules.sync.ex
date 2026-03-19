defmodule Mix.Tasks.Dev.UsageRules.Sync do
  use Mix.Task
  @shortdoc "Sync usage rules into ./rules without bloating AGENTS docs"

  @moduledoc """
  Sync package usage rules into the `rules/` folder and aggregate links in `rules/USAGE_RULES.md`.

  This avoids inlining large rule sets into AGENTS docs (keeps agent context small).

      mix dev.usage_rules.sync               # sync all (if usage_rules available)
      mix dev.usage_rules.sync ash ash_postgres  # sync selected packages
  """

  def run(args) do
    Mix.Task.run("app.start")
    File.mkdir_p!("rules")
    target = Path.join("rules", "USAGE_RULES.md")

    if Code.ensure_loaded?(Mix.Tasks.UsageRules.Sync) do
      # Build arguments: target file + packages (or --all), linked folder = rules/
      pkgs = if args == [] or Enum.member?(args, "--all"), do: ["--all"], else: args
      opts = ["--link-to-folder", "rules"]
      Mix.Task.run("usage_rules.sync", [target] ++ pkgs ++ opts)
      Mix.shell().info("✅ usage_rules synced to #{target}")
    else
      Mix.shell().info("ℹ️  usage_rules not available; skipping usage rules sync")
    end
  end
end

