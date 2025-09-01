defmodule Mix.Tasks.Spec.Ack do
  use Mix.Task
  @shortdoc "Create or update ack.json for a spec request and set status"
  @moduledoc """
  Usage:
    mix spec.ack --id <request_id> --owner name --contact contact \
                 [--eta 2025-09-02T12:00:00Z] [--branch feature/x] \
                 [--status accepted|in_progress|blocked] [--notes "..."]
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv,
      switches: [id: :string, owner: :string, contact: :string, eta: :string, branch: :string, status: :string, notes: :string]
    )

    id = req!(opts, :id)
    owner = req!(opts, :owner)
    contact = req!(opts, :contact)
    eta = Keyword.get(opts, :eta)
    branch = Keyword.get(opts, :branch)
    status = Keyword.get(opts, :status)
    notes = Keyword.get(opts, :notes)

    root = Path.join(["work", "spec_requests", id])
    File.dir?(root) || Mix.raise("Request not found: #{root}")

    ack_path = Path.join(root, "ack.json")
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    ack = File.exists?(ack_path) && Jason.decode!(File.read!(ack_path)) || %{}

    ack =
      ack
      |> Map.put("owner", owner)
      |> Map.put("contact", contact)
      |> maybe_put("eta_iso8601", eta)
      |> maybe_put("branch", branch)
      |> maybe_put("status", status)
      |> maybe_put("notes", notes)
      |> Map.put("updated_at", now)

    File.write!(ack_path, Jason.encode_to_iodata!(ack, pretty: true))

    if status in ["accepted", "in_progress", "blocked"] do
      File.write!(Path.join(root, status <> ".status"), "")
    end

    Mix.shell().info("Updated #{ack_path}")
  end

  defp req!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end
