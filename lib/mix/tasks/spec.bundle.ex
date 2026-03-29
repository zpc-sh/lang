defmodule Mix.Tasks.Spec.Bundle do
  use Mix.Task
  @shortdoc "Create a zip bundle for a spec request folder"
  @moduledoc """
  Usage:
    mix spec.bundle --id <request_id> [--out work/bundles/<id>.zip]

  Creates a zip archive containing `work/spec_requests/<id>/` suitable for
  dropping into another repo. By default, excludes `thread.md` (regenerable).
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string, out: :string])
    id = Keyword.get(opts, :id) || Mix.raise("Missing --id <request_id>")

    src_root = Path.join([File.cwd!(), "work", "spec_requests", id])
    File.dir?(src_root) || Mix.raise("Request folder not found: #{src_root}")

    out_dir = Path.join([File.cwd!(), "work", "bundles"]) 
    File.mkdir_p!(out_dir)
    out_path = Keyword.get(opts, :out) || Path.join(out_dir, id <> ".zip")

    # Collect files (exclude thread.md)
    files = Path.wildcard(Path.join(src_root, "**/*"), match_dot: true)
            |> Enum.filter(&File.regular?/1)
            |> Enum.reject(&(Path.basename(&1) == "thread.md"))

    if files == [] do
      Mix.raise("No files found to bundle in #{src_root}")
    end

    # Zip entry names include work/spec_requests/<id>/ prefix; let :zip read from cwd
    zip_prefix = Path.join(["work", "spec_requests", id])
    entries =
      Enum.map(files, fn path ->
        rel = Path.relative_to(path, src_root)
        zip_path = Path.join(zip_prefix, rel)
        String.to_charlist(zip_path)
      end)

    # Create zip
    case :zip.create(String.to_charlist(out_path), entries, []) do
      {:ok, _} ->
        Mix.shell().info("Created bundle: #{out_path}")
      {:error, reason} ->
        Mix.raise("Failed to create bundle: #{inspect(reason)}")
    end
  end
end
