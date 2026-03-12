defmodule Mix.Tasks.Spec.Attach do
  use Mix.Task
  @shortdoc "Attach a file to a spec request and update request.json"
  @moduledoc """
  Usage:
    mix spec.attach --to <request_id> --file path/to/file
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [to: :string, file: :string])
    id = require!(opts, :to)
    file = require!(opts, :file)

    root = Path.join(["work", "spec_requests", id])
    req_path = Path.join(root, "request.json")
    attachments_dir = Path.join(root, "attachments")
    File.mkdir_p!(attachments_dir)

    basename = Path.basename(file)
    dest = Path.join(attachments_dir, basename)
    File.cp!(file, dest)

    req = req_path |> File.read!() |> Jason.decode!()
    updated = Map.update(req, "attachments", [dest], fn list -> Enum.uniq(list ++ [dest]) end)
    File.write!(req_path, Jason.encode_to_iodata!(updated, pretty: true))
    Mix.shell().info("Attached #{basename} -> #{id}")
  end

  defp require!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
end
