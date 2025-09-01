defmodule Mix.Tasks.Spec.New do
  use Mix.Task
  @shortdoc "Scaffold a spec request under work/spec_requests/"
  @moduledoc """
  Creates a new spec request folder and request.json adhering to the local schema.

  Usage:
    mix spec.new <project> --title "..." [--slug slug] [--motivation "..."] [--priority high] [--version v1]

  Projects: jsonld | markdown_ld
  """

  @impl true
  def run([project | rest]) when project in ["jsonld", "markdown_ld"] do
    {opts, _, _} = OptionParser.parse(rest,
      switches: [title: :string, slug: :string, motivation: :string, priority: :string, version: :string]
    )

    title = required!(opts, :title)
    slug = Keyword.get(opts, :slug) || slugify(title)
    priority = Keyword.get(opts, :priority, "high")
    version = Keyword.get(opts, :version, "v1")

    id = id_for(project, slug)
    root = Path.join(["work", "spec_requests", id])
    File.mkdir_p!(root)

    request = %{
      project: project,
      title: title,
      motivation: Keyword.get(opts, :motivation, ""),
      api: %{},
      errors: [],
      determinism: [],
      telemetry: [],
      tests: [],
      acceptance: [],
      attachments: [],
      contacts: %{},
      meta: %{priority: priority, version: version}
    }

    File.write!(Path.join(root, "request.json"), Jason.encode_to_iodata!(request, pretty: true))
    File.write!(Path.join(root, "proposed.status"), "")

    Mix.shell().info("Created spec request: #{root}")
  end
  def run(_), do: Mix.raise("Usage: mix spec.new <jsonld|markdown_ld> --title \"...\"")

  defp required!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing required --#{key}")

  defp id_for(project, slug) do
    now = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.replace(~r/[-:]/, "")
    short = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
    "#{now}_#{project}_#{slug}_#{short}"
  end

  defp slugify(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
