defmodule Mix.Tasks.Spec.Msg.Pull do
  use Mix.Task
  @shortdoc "Pull peer outbox messages into local inbox"
  @moduledoc """
  Usage:
    mix spec.msg.pull --id <request_id> [--from /path/to/peer/work/spec_requests/<id>/outbox]
                      [--api https://cdfm.example.com] [--token <api-token>] [--since <iso8601>]

  If --from is omitted, builds it from SPEC_HANDOFF_DIR: $SPEC_HANDOFF_DIR/<id>/outbox
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string, from: :string, api: :string, token: :string, since: :string, workspace: :string])
    id = req!(opts, :id)
    dest_root = Path.join(["work", "spec_requests", id])
    inbox = Path.join(dest_root, "inbox")
    File.mkdir_p!(inbox)

    api = Keyword.get(opts, :api)
    token = Keyword.get(opts, :token) || System.get_env("CDFM_API_TOKEN")
    workspace = Keyword.get(opts, :workspace) || System.get_env("CDFM_WORKSPACE_ID")
    since = Keyword.get(opts, :since)

    if api do
      pull_via_api(id, api, token, workspace, since)
    else
      from_outbox =
        case Keyword.get(opts, :from) do
          nil ->
            base = System.get_env("SPEC_HANDOFF_DIR") || Mix.raise("Provide --from or set SPEC_HANDOFF_DIR")
            Path.join([base, id, "outbox"])
          v -> v
        end

      for msg_path <- Path.wildcard(Path.join(from_outbox, "msg_*.json")) do
        File.cp!(msg_path, Path.join(inbox, Path.basename(msg_path)))
        Mix.shell().info("Pulled #{Path.basename(msg_path)}")
      end
    end
  end

  defp req!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")

  defp pull_via_api(id, base_url, token, workspace, since) do
    root = Path.join(["work", "spec_requests", id])
    inbox = Path.join(root, "inbox")
    atts_dir = Path.join(root, "attachments")
    File.mkdir_p!(inbox)
    File.mkdir_p!(atts_dir)

    messages = Lang.Spec.CDFMClient.fetch_messages(base_url, token, workspace, id, since)
    Enum.each(messages, fn m ->
      msg_id = m["id"] || m[:id] || Base.encode16(:crypto.hash(:sha256, Jason.encode!(m)), case: :lower) |> binary_part(0, 16)
      file = Path.join(inbox, "msg_" <> msg_id <> ".json")
      File.write!(file, Jason.encode_to_iodata!(m, pretty: true))

      case Map.get(m, "attachments_content") || Map.get(m, :attachments_content) do
        nil -> :ok
        att_map when is_map(att_map) ->
          Enum.each(att_map, fn {rel, b64} ->
            target = Path.join(root, rel)
            File.mkdir_p!(Path.dirname(target))
            File.write!(target, Base.decode64!(b64))
          end)
      end

      Mix.shell().info("Pulled #{Path.basename(file)} from CDFM")
    end)
  end
end
