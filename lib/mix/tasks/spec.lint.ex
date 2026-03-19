defmodule Mix.Tasks.Spec.Lint do
  use Mix.Task
  @shortdoc "Validate request, ack, and messages; check attachments; render thread"
  @moduledoc """
  Usage:
    mix spec.lint --id <request_id>

  Performs lightweight checks:
  - request.json exists and is valid JSON
  - ack.json (if present) is valid JSON
  - messages in inbox/outbox are valid JSON and have bodies
  - attachments referenced by messages exist
  - renders thread.md successfully
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string])
    id = Keyword.get(opts, :id) || Mix.raise("Missing --id")

    root = Path.join(["work", "spec_requests", id])
    req_path = Path.join(root, "request.json")
    ack_path = Path.join(root, "ack.json")

    ok =
      file_json(req_path, "request.json") and
      optional_json(ack_path, "ack.json") and
      messages_ok?(root) and
      render_ok?(id)

    if ok, do: Mix.shell().info("Lint OK for #{id}"), else: Mix.raise("Lint failed for #{id}")
  end

  defp file_json(path, label) do
    with true <- File.exists?(path) || (Mix.shell().error("Missing #{label}"); false),
         {:ok, _} <- decode(path) do
      true
    else
      _ -> false
    end
  end

  defp optional_json(path, _label) do
    if File.exists?(path) do
      case decode(path) do
        {:ok, _} -> true
        _ -> (Mix.shell().error("Invalid JSON: #{path}"); false)
      end
    else
      true
    end
  end

  defp decode(path) do
    try do
      {:ok, Jason.decode!(File.read!(path))}
    rescue
      _ -> {:error, :invalid}
    end
  end

  defp messages_ok?(root) do
    [Path.join(root, "inbox"), Path.join(root, "outbox")]
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "msg_*.json")))
    |> Enum.map(fn mpath ->
      case decode(mpath) do
        {:ok, m} ->
          body_ok = is_binary(m["body"]) and byte_size(m["body"]) > 0
          atts_ok = Enum.all?(m["attachments"] || [], fn rel -> File.exists?(Path.join(root, rel)) end)
          if not body_ok, do: Mix.shell().error("Empty body: #{mpath}")
          if not atts_ok, do: Mix.shell().error("Missing attachment for #{mpath}")
          body_ok and atts_ok
        _ -> Mix.shell().error("Invalid message JSON: #{mpath}"); false
      end
    end)
    |> Enum.all?()
  end

  defp render_ok?(id) do
    try do
      Mix.Task.run("spec.thread.render", ["--id", id])
      true
    rescue
      e -> Mix.shell().error("thread render failed: #{inspect(e)}"); false
    end
  end
end
