defmodule Mix.Tasks.Spec.Export.Jsonld do
  use Mix.Task
  @shortdoc "Export request, ack, and messages as JSON-LD into the hub"
  @moduledoc """
  Usage:
    mix spec.export.jsonld --id <req> --project <name> --hub ../lang-spec-hub \
                           [--api https://cdfm.example.com] [--token <api-token>]

  Writes JSON-LD files under <hub>/requests/<project>/<id>/jsonld/ using the hub context path:
    ../../../schemas/contexts/spec.jsonld
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string, project: :string, hub: :string, api: :string, token: :string, workspace: :string])
    id = req!(opts, :id)
    project = req!(opts, :project)
    hub = req!(opts, :hub)

    dest_root = Path.join([hub, "requests", project, id, "jsonld"]) 
    File.mkdir_p!(dest_root)

    context_rel = Path.join(["..", "..", "..", "schemas", "contexts", "spec.jsonld"]) # ../../../schemas/contexts/spec.jsonld

    case Keyword.get(opts, :api) do
      nil -> export_from_filesystem(id, project, dest_root, context_rel)
      api -> export_from_cdfm(api, Keyword.get(opts, :token) || System.get_env("CDFM_API_TOKEN"), Keyword.get(opts, :workspace) || System.get_env("CDFM_WORKSPACE_ID"), id, project, dest_root)
    end

    Mix.shell().info("Exported JSON-LD to #{dest_root}")
  end

  defp read_json!(path), do: Jason.decode!(File.read!(path))
  defp write_json!(path, map), do: File.write!(path, Jason.encode_to_iodata!(map, pretty: true))

  defp export_from_filesystem(id, project, dest_root, context_rel) do
    src_root = Path.join([File.cwd!(), "work", "spec_requests", id])
    File.dir?(src_root) || Mix.raise("Request not found: #{src_root}")

    # request
    req_json = read_json!(Path.join(src_root, "request.json"))
    statuses = status_list(src_root)
    req_ld = %{
      "@context" => context_rel,
      "@id" => "urn:spec:" <> project <> ":" <> id,
      "@type" => "SpecRequest",
      "project" => project,
      "title" => req_json["title"],
      "motivation" => req_json["motivation"],
      "api" => req_json["api"],
      "errors" => req_json["errors"],
      "determinism" => req_json["determinism"],
      "telemetry" => req_json["telemetry"],
      "tests" => req_json["tests"],
      "acceptance" => req_json["acceptance"],
      "attachments" => req_json["attachments"],
      "statuses" => statuses,
      "status" => List.last(statuses || ["proposed"]),
      "updatedAt" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    write_json!(Path.join(dest_root, "request.jsonld"), req_ld)

    # ack (optional)
    ack_path = Path.join(src_root, "ack.json")
    if File.exists?(ack_path) do
      ack_json = read_json!(ack_path)
      ack_ld = %{
        "@context" => context_rel,
        "@id" => "urn:specack:" <> project <> ":" <> id,
        "@type" => "SpecAck",
        "owner" => ack_json["owner"],
        "contact" => ack_json["contact"],
        "status" => ack_json["status"],
        "eta" => ack_json["eta_iso8601"],
        "updatedAt" => ack_json["updated_at"]
      }
      write_json!(Path.join(dest_root, "ack.jsonld"), ack_ld)
    end

    # messages (inbox + outbox)
    for dir <- ["inbox", "outbox"] do
      Path.wildcard(Path.join(src_root, dir <> "/msg_*.json"))
      |> Enum.each(fn msg_path ->
        m = read_json!(msg_path)
        basename = Path.basename(msg_path) |> String.replace(~r/\.json$/, "")
        msg_ld = %{
          "@context" => context_rel,
          "@id" => "urn:specmsg:" <> project <> ":" <> id <> ":" <> basename,
          "@type" => "SpecMessage",
          "from" => m["from"],
          "type" => m["type"],
          "ref" => m["ref"],
          "body" => m["body"],
          "attachments" => m["attachments"],
          "relatesTo" => "urn:spec:" <> project <> ":" <> id,
          "status" => m["status"],
          "createdAt" => m["created_at"],
          "updatedAt" => m["updated_at"]
        }
        out_dir = Path.join(dest_root, "messages")
        File.mkdir_p!(out_dir)
        write_json!(Path.join(out_dir, basename <> ".jsonld"), msg_ld)
      end)
    end
  end

  defp export_from_cdfm(api, token, workspace, id, project, dest_root) do
    data = Lang.Spec.CDFMClient.fetch_export_jsonld(api, token, workspace, id)
    # The API may either return a single request doc or a struct with keys
    # like %{"request" => ..., "ack" => ..., "messages" => [...]}
    case data do
      %{"@type" => type} when type in ["SpecRequest", :SpecRequest] ->
        write_json!(Path.join(dest_root, "request.jsonld"), data)
      %{"request" => req} ->
        write_json!(Path.join(dest_root, "request.jsonld"), req)
      other ->
        write_json!(Path.join(dest_root, "request.jsonld"), other)
    end

    case data do
      %{"ack" => ack} when is_map(ack) -> write_json!(Path.join(dest_root, "ack.jsonld"), ack)
      _ -> :ok
    end

    msgs =
      case data do
        %{"messages" => list} when is_list(list) -> list
        _ -> []
      end

    out_dir = Path.join(dest_root, "messages")
    File.mkdir_p!(out_dir)

    Enum.with_index(msgs, 1)
    |> Enum.each(fn {m, idx} ->
      basename = basename_for_msg(m, idx)
      write_json!(Path.join(out_dir, basename <> ".jsonld"), m)
    end)
  end

  defp basename_for_msg(m, idx) do
    cond do
      is_binary(m["@id"]) ->
        m["@id"]
        |> String.split([":", "/"]) |> List.last()
        |> String.replace(~r/[^a-zA-Z0-9_\-\.]/, "_")
      is_binary(m["id"]) ->
        "msg_" <> (m["id"] |> String.replace(~r/[^a-zA-Z0-9_\-\.]/, "_"))
      true ->
        "msg_" <> Integer.to_string(idx)
    end
  end
  defp status_list(root) do
    Path.wildcard(Path.join(root, "*.status"))
    |> Enum.map(&Path.basename/1)
    |> Enum.map(&String.trim_trailing(&1, ".status"))
    |> Enum.sort()
  end

  defp req!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
end
