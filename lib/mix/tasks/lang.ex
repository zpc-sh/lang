defmodule Mix.Tasks.Lang do
  @moduledoc """
  Lists all available LANG-specific Mix tasks.

  ## Usage

      mix lang
      
  This will show all available lang.* tasks with descriptions.
  """

  use Mix.Task

  @shortdoc "List all LANG Mix tasks"

  def run(_args) do
    Mix.shell().info("""
    🚀 LANG Mix Tasks
    =================

    Project Analysis & Cleanup:
      mix lang.audit.parsers      - Audit parser usage and dependencies
      mix lang.cleanup            - Clean up project structure
      mix lang.refactor.parsers   - Refactor parser modules

    Development Tools:
      mix precommit              - Run pre-commit checks
      mix quality                - Run code quality checks
      
    Use `mix help TASK` for more information about a specific task.

    Examples:
      mix lang.audit.parsers --format json
      mix lang.cleanup analyze
      mix lang.refactor.parsers plan
    """)
  end
end
