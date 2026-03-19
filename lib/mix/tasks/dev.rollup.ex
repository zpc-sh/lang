defmodule Mix.Tasks.Dev.Rollup do
  use Mix.Task
  @shortdoc "Run repo control and packaging tasks (docs policy, scan, JWKS, assets deploy)"

  def run(args) do
    Mix.Task.run("app.start")
    strict = Enum.member?(args, "--strict")

    # Enforce docs policy (placement + trusted frontmatter)
    Mix.Task.run("dev.docs_policy")

    # Scan docs for injections (fail on high; --strict fails on medium too)
    scan_args = if strict, do: ["--fail-on", "medium"], else: ["--fail-on", "high"]
    Mix.Task.run("dev.docs_scan", scan_args)

    # Generate JWKS if possible
    Mix.Task.run("dev.gen_jwks")

    # Build and copy static assets (including .well-known)
    Mix.Task.run("assets.deploy")

    # Enforce tests policy (no scattered tests)
    Mix.Task.run("dev.tests_policy")

    # Sync usage rules (links only) into ./rules to avoid bloating AGENTS docs
    try do
      Mix.Task.run("dev.usage_rules.sync", ["--all"]) 
    rescue
      _ -> :ok
    end

    Mix.shell().info("✅ Rollup complete")
  end
end

