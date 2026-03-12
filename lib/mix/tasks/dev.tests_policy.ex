defmodule Mix.Tasks.Dev.TestsPolicy do
  use Mix.Task
  @shortdoc "Enforce tests live under ./test and not scattered"

  @moduledoc """
  Fails if any *_test.exs files are found outside the ./test directory.

      mix dev.tests_policy
  """

  def run(_args) do
    Mix.Task.run("app.start")
    offenders = find_offenders()
    if offenders == [] do
      Mix.shell().info("✅ Tests policy OK (no scattered tests)")
    else
      Mix.shell().error("❌ Found test files outside ./test:")
      Enum.each(offenders, &Mix.shell().error("   " <> &1))
      Mix.raise("tests policy violation")
    end
  end

  defp find_offenders do
    root = File.cwd!()
    all = Path.wildcard(Path.join(root, "**/*_test.exs"), match_dot: false)
    Enum.filter(all, fn path ->
      rel = Path.relative_to(path, root)
      not String.starts_with?(rel, "test/")
    end)
  end
end

