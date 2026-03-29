
defmodule Mix.Tasks.Dev.Events.Sync do
  use Mix.Task
  @shortdoc "Generate event docs and enforce registry lint"

  @moduledoc """
  Convenience task that regenerates the canonical event docs from the
  TypeRegistry and runs the registry lint in fail mode.

      mix dev.events.sync
  """

  def run(_args) do
    Mix.Task.run("app.start")
    Mix.Task.run("dev.events.docs")
    Mix.Tasks.Dev.Events.Lint.run(["--fail"])
  end
end
