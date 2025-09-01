defmodule Mix.Tasks.Spec.Hub.Validate do
  use Mix.Task
  @shortdoc "Validate hub JSON-LD export for a request against expected shape/context"
  @moduledoc """
  Usage:
    mix spec.hub.validate --id <request_id> --project <name> --hub ../lang-spec-hub

  Validates that <hub>/requests/<project>/<id>/jsonld contains a canonical
  JSON-LD export with required files and fields:
  - request.jsonld exists and has @context and @type==SpecRequest
  - optional ack.jsonld has @type==SpecAck
  - messages/*.jsonld have @type==SpecMessage and correct relatesTo
  - all JSON-LD docs use the expected context path

  Notes:
  - This is a lightweight structural validator. For deep schema checks, we can
    extend to full JSON Schema later if desired.
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string, project: :string, hub: :string])
    id = req!(opts, :id)
    project = req!(opts, :project)
    hub = req!(opts, :hub)

    base = Path.join([hub, "requests", project, id, "jsonld"]) 
    File.dir?(base) || Mix.raise("JSON-LD folder not found: #{base}")

    expected_context = Path.join(["..", "..", "..", "schemas", "contexts", "spec.jsonld"]) # ../../../schemas/contexts/spec.jsonld
    relates_to = "urn:spec:" <> project <> ":" <> id

    errors = []

    # request.jsonld
    req_path = Path.join(base, "request.jsonld")
    errors =
      if File.exists?(req_path) do
        req = read_json!(req_path)
        []
        |> expect(req, req_path, "@context", expected_context)
        |> expect(req, req_path, "@type", "SpecRequest")
        |> expect(req, req_path, "project", project)
        |> expect_present(req, req_path, "title")
        |> then(fn e -> errors ++ e end)
      else
        ["Missing file: #{rel(req_path, hub)}"]
      end

    # ack.jsonld (optional)
    ack_path = Path.join(base, "ack.jsonld")
    errors =
      if File.exists?(ack_path) do
        ack = read_json!(ack_path)
        errors
        |> expect(ack, ack_path, "@context", expected_context)
        |> expect(ack, ack_path, "@type", "SpecAck")
      else
        errors
      end

    # messages
    msg_dir = Path.join(base, "messages")
    errors =
      if File.dir?(msg_dir) do
        Enum.reduce(Path.wildcard(Path.join(msg_dir, "*.jsonld")), errors, fn path, acc ->
          m = read_json!(path)
          acc
          |> expect(m, path, "@context", expected_context)
          |> expect(m, path, "@type", "SpecMessage")
          |> expect(m, path, "relatesTo", relates_to)
        end)
      else
        ["Missing folder: #{rel(msg_dir, hub)}" | errors]
      end

    if errors == [] do
      Mix.shell().info("Hub JSON-LD validation OK for #{project}/#{id}")
    else
      Enum.each(Enum.reverse(errors), &Mix.shell().error("- " <> &1))
      Mix.raise("Validation failed with #{length(errors)} error(s)")
    end
  end

  defp read_json!(path), do: Jason.decode!(File.read!(path))

  defp expect(errors, map, path, key, expected) do
    actual = Map.get(map, key)
    if actual == expected, do: errors, else: ["#{rel(path)}: expected #{key}=#{inspect(expected)}, got #{inspect(actual)}" | errors]
  end

  defp expect_present(errors, map, path, key) do
    if Map.has_key?(map, key) && not is_nil(Map.get(map, key)), do: errors, else: ["#{rel(path)}: missing required key #{key}" | errors]
  end

  defp rel(path), do: Path.relative_to(path, File.cwd!())
  defp rel(path, base), do: Path.relative_to(path, base)

  defp req!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
end

