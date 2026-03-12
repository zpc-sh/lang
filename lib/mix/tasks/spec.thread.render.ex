defmodule Mix.Tasks.Spec.Thread.Render do
  use Mix.Task
  @shortdoc "Render a single Markdown thread file from request + messages"
  @moduledoc """
  Usage:
    mix spec.thread.render --id <request_id>

  Renders `work/spec_requests/<id>/thread.md` combining request.json and all inbox/outbox messages
  in chronological order, as a single Markdown file suitable for review by both sides.
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string])
    id = Keyword.get(opts, :id) || Mix.raise("Missing --id")

    root = Path.join(["work", "spec_requests", id])
    req_path = Path.join(root, "request.json")
    request = File.exists?(req_path) && Jason.decode!(File.read!(req_path)) || %{}

    msgs =
      [Path.join(root, "inbox"), Path.join(root, "outbox")]
      |> Enum.flat_map(fn dir -> Path.wildcard(Path.join(dir, "msg_*.json")) end)
      |> Enum.map(&{&1, Jason.decode!(File.read!(&1))})
      |> Enum.sort_by(fn {_p, m} -> m["created_at"] || m["id"] end)

    out = ["# Spec Thread: #{id}\n\n"]
    out = out ++ ["## Request\n\n", "```json\n", Jason.encode!(request, pretty: true), "\n```\n\n"]

    out =
      Enum.reduce(msgs, out, fn {path, m}, acc ->
        header = "### [#{m["type"]}] #{m["from"]["project"]}/#{m["from"]["agent"]} @ #{m["created_at"]}\n\n"
        ref =
          case m["ref"] do
            nil -> ""
            %{"path" => p} = r -> "Ref: #{p} #{r["json_pointer"] || ""}\n\n"
            _ -> ""
          end
        body = m["body"] || ""
        files = m["attachments"] || []
        files_block = if files == [], do: "", else: "Attachments:\n\n" <> Enum.map_join(files, "\n", &("- " <> &1)) <> "\n\n"
        acc ++ [header, ref, body, "\n\n", files_block]
      end)

    thread_path = Path.join(root, "thread.md")
    File.write!(thread_path, IO.iodata_to_binary(out))
    Mix.shell().info("Rendered #{thread_path}")
  end
end
