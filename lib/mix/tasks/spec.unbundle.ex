defmodule Mix.Tasks.Spec.Unbundle do
  use Mix.Task
  @shortdoc "Extract a spec request zip bundle into this repo"
  @moduledoc """
  Usage:
    mix spec.unbundle --zip work/bundles/<id>.zip [--dest .]

  Extracts the bundle into `--dest` (default: repo root), preserving the
  `work/spec_requests/<id>/...` prefix contained in the archive.
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [zip: :string, dest: :string])
    zip_path = Keyword.get(opts, :zip) || Mix.raise("Missing --zip <path-to-bundle.zip>")
    dest = Keyword.get(opts, :dest, File.cwd!())

    File.exists?(zip_path) || Mix.raise("Zip not found: #{zip_path}")
    File.dir?(dest) || Mix.raise("Dest is not a directory: #{dest}")

    {:ok, _files} = :zip.extract(String.to_charlist(zip_path), cwd: String.to_charlist(dest))
    Mix.shell().info("Extracted #{zip_path} -> #{dest}")
  end
end
