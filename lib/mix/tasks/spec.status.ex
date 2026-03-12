defmodule Mix.Tasks.Spec.Status do
  use Mix.Task
  @shortdoc "Set or show status for a spec request"
  @moduledoc """
  Usage:
    mix spec.status --id <request_id> --set proposed|accepted|in_progress|implemented|rejected|blocked \
                    [--api https://cdfm.example.com] [--token <api-token>]
  """

  @statuses ~w[proposed accepted in_progress implemented rejected blocked]

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string, set: :string, api: :string, token: :string, workspace: :string])
    id = require!(opts, :id)
    set = Keyword.get(opts, :set)

    root = Path.join(["work", "spec_requests", id])
    File.mkdir_p!(root)

    if is_nil(set) do
      statuses = Enum.filter(@statuses, &File.exists?(Path.join(root, &1 <> ".status")))
      Mix.shell().info("Statuses for #{id}: #{Enum.join(statuses, ", ")}")
    else
      valid?(set) || Mix.raise("Invalid status: #{set}")
      File.write!(Path.join(root, set <> ".status"), "")
      # Optional API sync
      case Keyword.get(opts, :api) do
        nil -> :ok
        api ->
          token = Keyword.get(opts, :token) || System.get_env("CDFM_API_TOKEN")
          workspace = Keyword.get(opts, :workspace) || System.get_env("CDFM_WORKSPACE_ID")
          _ = Lang.Spec.CDFMClient.set_status(api, token, workspace, id, set)
      end
      Mix.shell().info("Set status=#{set} for #{id}")
    end
  end

  defp require!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
  defp valid?(val), do: val in @statuses
end
