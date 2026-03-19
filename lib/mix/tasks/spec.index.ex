defmodule Mix.Tasks.Spec.Index do
  use Mix.Task
  @shortdoc "Generate or refresh index.md for a spec-hub"
  @moduledoc """
  Usage:
    mix spec.index --hub ../lang-spec-hub

  Scans `<hub>/requests/<project>/<id>` and writes `<hub>/index.md` grouped by project
  and sorted by updated time from request.json/ack.json or file mtimes.
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [hub: :string])
    hub = Keyword.get(opts, :hub) || Mix.raise("Missing --hub")

    req_root = Path.join(hub, "requests")
    projects = Path.wildcard(Path.join(req_root, "*")) |> Enum.filter(&File.dir?/1)

    sections =
      Enum.map(projects, fn proj_dir ->
        project = Path.basename(proj_dir)
        rows = entries_for_project(proj_dir, project)
        ["## ", project, "\n\n", rows, "\n"]
      end)
      |> IO.iodata_to_binary()

    content = [
      "# Spec Hub Index\n\n",
      "Generated at ", DateTime.utc_now() |> DateTime.to_iso8601(), "\n\n",
      sections
    ] |> IO.iodata_to_binary()

    File.write!(Path.join(hub, "index.md"), content)
    Mix.shell().info("Updated #{Path.join(hub, "index.md")}")
  end

  defp entries_for_project(dir, project) do
    ids = Path.wildcard(Path.join(dir, "*")) |> Enum.filter(&File.dir?/1) |> Enum.map(&Path.basename/1)
    items = Enum.map(ids, fn id -> {id, info_for(Path.join(dir, id))} end)
    items = Enum.sort_by(items, fn {_id, info} -> info.updated end, {:desc, DateTime})

    [
      table_header(),
      Enum.map(items, fn {id, info} -> table_row(project, id, info) end)
    ]
  end

  defp info_for(path) do
    req = maybe_decode(Path.join(path, "request.json")) || %{}
    ack = maybe_decode(Path.join(path, "ack.json")) || %{}
    statuses = Path.wildcard(Path.join(path, "*.status")) |> Enum.map(&Path.basename/1) |> Enum.map(&String.trim_trailing(&1, ".status"))
    updated =
      ["ack.json", "request.json", "thread.md"]
      |> Enum.map(&Path.join(path, &1))
      |> Enum.filter(&File.exists?/1)
      |> Enum.map(&mtime!/1)
      |> Enum.max_by(& &1, fn -> DateTime.from_unix!(0) end)
    %{title: req["title"], statuses: statuses, request: req, ack: ack, updated: updated}
  end

  defp table_header do
    [
      "| Status | ID | Title | Updated | Links |\n",
      "|:------:|:----|:------|:--------|:------|\n"
    ]
  end

  defp table_row(project, id, %{title: title, statuses: statuses, updated: updated}) do
    updated_str = case updated do
      %DateTime{} = dt -> dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      _ -> ""
    end
    req_link = ["[request](requests/", project, "/", id, "/request.json)"]
    thread_link = ["[thread](requests/", project, "/", id, "/thread.md)"]
    links = [thread_link, " · ", req_link]
    [
      "| ", status_badges(statuses),
      " | ", id,
      " | ", (title || "(no title)"),
      " | ", (updated_str == "" && "" || updated_str),
      " | ", links, " |\n"
    ]
  end

  defp status_badges([]), do: badge("proposed")
  defp status_badges(list) when is_list(list) do
    list
    |> Enum.map(&badge/1)
    |> Enum.join(" ")
  end

  defp badge("proposed"), do: "🟡 proposed"
  defp badge("accepted"), do: "🟢 accepted"
  defp badge("in_progress"), do: "🔵 in_progress"
  defp badge("done"), do: "✅ done"
  defp badge("rejected"), do: "⛔ rejected"
  defp badge("blocked"), do: "🟥 blocked"
  defp badge(other) when is_binary(other), do: other

  defp maybe_decode(path) do
    if File.exists?(path) do
      try do
        Jason.decode!(File.read!(path))
      rescue
        _ -> nil
      end
    else
      nil
    end
  end

  defp mtime!(path) do
    {:ok, stat} = File.stat(path)
    stat.mtime |> NaiveDateTime.to_erl() |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
  end
end
