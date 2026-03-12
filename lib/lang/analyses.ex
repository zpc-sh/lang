defmodule Lang.Analyses do
  @moduledoc """
  Ash domain for analysis runs, files, and violations.

  This domain centralizes resources previously under Lang.Analysis.*.
  """

  use Ash.Domain

  resources do
    # Keep Project for now (legacy grouping)
    resource(Lang.Analyses.Project)

    # New canonical resource modules
    resource(Lang.Analyses.Run)
    resource(Lang.Analyses.File)
    resource(Lang.Analyses.Violation)
  end
end
