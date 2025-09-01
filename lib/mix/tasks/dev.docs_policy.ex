defmodule Mix.Tasks.Dev.DocsPolicy do
  use Mix.Task
  @shortdoc "Enforce docs policy: trusted frontmatter and markdown placement"

  @moduledoc """
  Checks that:
  - All markdown under ./docs contains YAML frontmatter with `trusted: true`
  - Markdown outside ./docs is allowlisted in `.doc_allowlist`

      mix dev.docs_policy
  """

  def run(_args) do
    Mix.Task.run("app.start")

    outside = Lang.Dev.DocPolicy.untrusted_markdown_outside_docs()
    missing = Lang.Dev.DocPolicy.check_trusted_frontmatter()

    cond do
      outside != [] ->
        Mix.shell().error("❌ Markdown found outside ./docs and not allowlisted:")
        Enum.each(outside, &Mix.shell().error("   " <> &1))
        Mix.raise("docs policy violation")

      missing != [] ->
        Mix.shell().error("❌ Trusted docs missing `trusted: true` frontmatter:")
        Enum.each(missing, fn {p, _} -> Mix.shell().error("   " <> p) end)
        Mix.raise("docs policy violation")

      true ->
        Mix.shell().info("✅ Docs policy checks passed")
    end
  end
end

