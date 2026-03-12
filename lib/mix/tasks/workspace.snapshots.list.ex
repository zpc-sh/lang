
defmodule Mix.Tasks.Workspace.Snapshots.List do
  use Mix.Task
  @shortdoc "List recent workspace snapshot keys in S3"

  @moduledoc """
  List snapshot objects from S3 for a repository triple.

  Options:
  --repo "org/user/workspace"   Repository triple (required unless --prefix given)
  --limit N                     Max results (default 20)
  --prefix PREFIX               Override S3 key prefix
  --presign                     Print presigned GET URLs instead of keys
  """

  @switches [repo: :string, limit: :integer, prefix: :string, presign: :boolean, format: :string]

  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: @switches)

    prefix =
      cond do
        is_binary(opts[:prefix]) -> opts[:prefix]
        repo = parse_repo(opts[:repo]) ->
          "org/#{repo["org"]}/user/#{repo["user"]}/workspaces/#{repo["workspace"]}/snapshots/"
        true -> Mix.raise("--repo or --prefix is required")
      end

    limit = opts[:limit] || 20
    case Lang.Storage.S3.list_objects(prefix, max_keys: limit) do
      {:ok, objs} ->
        items =
          objs
          |> Enum.sort_by(&(&1.last_modified), :desc)
          |> Enum.take(limit)
          |> Enum.map(fn o ->
            if opts[:presign] do
              case Lang.Storage.S3.presign_get(o.key) do
                {:ok, url} -> Map.put(o, :url, url)
                _ -> o
              end
            else
              o
            end
          end)

        case String.downcase(to_string(opts[:format] || "")) do
          "json" ->
            json_items = Enum.map(items, fn m -> for {k,v} <- m, into: %{}, do: {to_string(k), v} end)
            Mix.shell().info(Jason.encode!(json_items, pretty: true))
          _ ->
            Enum.each(items, fn o ->
              line = o[:url] || o.key
              Mix.shell().info(line)
            end)
        end
      other -> Mix.raise("S3 list failed: #{inspect(other)}")
    end
  end

  defp parse_repo(nil), do: nil
  defp parse_repo(str) do
    case String.split(str || "", "/") do
      [org, user, ws] -> %{"org" => org, "user" => user, "workspace" => ws}
      _ -> nil
    end
  end
end
