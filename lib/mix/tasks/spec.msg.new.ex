defmodule Mix.Tasks.Spec.Msg.New do
  use Mix.Task
  @shortdoc "Create a message JSON in outbox for a spec request"
  @moduledoc """
  Usage:
    mix spec.msg.new --id <request_id> --type comment|question|proposal|decision \
                     --body path/to/body.md \
                     [--from-project lang] [--from-agent codex] \
                     [--ref-path request.json] [--ref-pointer /api/hash] \
                     [--attach file1 --attach file2]
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv,
      switches: [
        id: :string,
        type: :string,
        body: :string,
        from_project: :string,
        from_agent: :string,
        ref_path: :string,
        ref_pointer: :string,
        attach: :keep
      ]
    )

    id = req!(opts, :id)
    type = req!(opts, :type)
    body_path = req!(opts, :body)
    from_project = Keyword.get(opts, :from_project, "lang")
    from_agent = Keyword.get(opts, :from_agent, "codex")
    ref_path = Keyword.get(opts, :ref_path)
    ref_pointer = Keyword.get(opts, :ref_pointer)
    attachments = opts |> Keyword.get_values(:attach)

    root = Path.join(["work", "spec_requests", id])
    outbox = Path.join(root, "outbox")
    atts_dir = Path.join(root, "attachments")
    File.mkdir_p!(outbox)
    File.mkdir_p!(atts_dir)

    body = File.read!(body_path)

    msg_id = gen_msg_id()
    msg = %{
      id: msg_id,
      from: %{project: from_project, agent: from_agent},
      type: type,
      ref: ref_path || ref_pointer && %{path: ref_path, json_pointer: ref_pointer} || nil,
      body: body,
      attachments: [],
      relates_to: %{request_id: id},
      status: "open",
      created_at: now(),
      updated_at: now()
    }

    # copy attachments if provided
    msg =
      Enum.reduce(attachments, msg, fn file, acc ->
        dest = Path.join(atts_dir, Path.basename(file))
        File.cp!(file, dest)
        Map.update!(acc, :attachments, fn list -> list ++ [Path.relative_to(dest, root)] end)
      end)

    msg_path = Path.join(outbox, "msg_" <> msg_id <> ".json")
    File.write!(msg_path, Jason.encode_to_iodata!(msg, pretty: true))
    Mix.shell().info("Created message: #{msg_path}")
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
  defp req!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
  defp gen_msg_id do
    ts = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(~r/[:]/, "")
    sh = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
    ts <> "-" <> sh
  end
end
