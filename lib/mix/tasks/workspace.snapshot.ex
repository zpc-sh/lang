

defmodule Mix.Tasks.Workspace.Snapshot do
  use Mix.Task
  @shortdoc "Enqueue a workspace snapshot to S3"

  @moduledoc """
  Enqueue a workspace filesystem snapshot and store it in S3 as gzipped JSON.

  Options:
  --repo "org/user/workspace"   Repository triple (preferred)
  --workspace-id ID             Workspace ID (alternative)
  --root PATH                   Explicit workspace root path (fast path)
  --reduce MODE                 manifest_only | with_previews | stats_only | stats_only_by_kind
  --max-depth N                 Scan depth (default 12)
  --max-files N                 Max files in manifest (default 5000)
  --max-total-size BYTES        Max aggregated bytes in manifest (default unlimited)
  --include-glob PATTERN        Include glob (repeatable)
  --exclude-glob PATTERN        Exclude glob (repeatable)
  --key KEY                     Override S3 key
  --print                       Print summary locally (no enqueue)
  --dry-run                     After print, prompt to enqueue
  --format json                 When printing, output JSON instead of table

  Examples:
    mix workspace.snapshot --repo "acme/jane/web" --reduce stats_only_by_kind
    mix workspace.snapshot --workspace-id 123e4567-... --reduce manifest_only
    mix workspace.snapshot --root . --include-glob "**/*.ex" --exclude-glob "**/deps/**"
  """

  @switches [
    repo: :string,
    "workspace-id": :string,
    root: :string,
    reduce: :string,
    "max-depth": :integer,
    "max-files": :integer,
    "max-total-size": :integer,
    "include-glob": :keep,
    "exclude-glob": :keep,
    key: :string,
    print: :boolean,
    "dry-run": :boolean,
    format: :string,
    top: :integer
  ]

  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: @switches)

    repo = parse_repo(opts[:repo])
    wid = opts[:"workspace-id"]
    root = opts[:root]
    reduce = opts[:reduce] || "manifest_only"
    max_depth = opts[:"max-depth"] || 12
    max_files = opts[:"max-files"] || 5_000
    max_total_size = opts[:"max-total-size"]
    include_globs = List.wrap(opts[:"include-glob"]) |> Enum.reject(&is_nil/1)
    exclude_globs = List.wrap(opts[:"exclude-glob"]) |> Enum.reject(&is_nil/1)
    key = opts[:key]

    params = %{}
    params = if repo, do: Map.put(params, "repository", repo), else: params
    params = if wid, do: Map.put(params, "workspace_id", wid), else: params
    params = if root, do: Map.put(params, "workspace_root", root), else: params
    params =
      params
      |> Map.merge(%{
        "reduce" => reduce,
        "max_depth" => max_depth,
        "max_files" => max_files,
        "include_globs" => include_globs,
        "exclude_globs" => exclude_globs
      })
    params = if key, do: Map.put(params, "key", key), else: params
    params = if max_total_size, do: Map.put(params, "max_total_size", max_total_size), else: params

    if opts[:print] do
      resolved_root = resolve_print_root(root, repo, wid)

      {:ok, reduced} = Lang.Workers.WorkspaceSnapshotWorker.scan_and_reduce(resolved_root,
        max_depth: max_depth,
        reduce: reduce,
        max_files: max_files,
        include_globs: include_globs,
        exclude_globs: exclude_globs,
        max_total_size: max_total_size || :infinity
      )

      case String.downcase(to_string(opts[:format] || "")) do
        "json" ->
          top = opts[:top] || 10
          if Map.get(reduced, :kind) == "stats_only_by_kind" or Map.get(reduced, "kind") == "stats_only_by_kind" do
            by_kind = Map.get(reduced, :stats_by_kind) || Map.get(reduced, "stats_by_kind") || %{}
            items = by_kind |> Enum.sort_by(fn {_k, v} -> -(v[:count] || v["count"] || 0) end) |> Enum.take(top)
            arr = Enum.map(items, fn {k, v} -> %{kind: to_string(k), count: v[:count] || v["count"] || 0, bytes: v[:bytes] || v["bytes"] || 0} end)
            Mix.shell().info(Jason.encode!(arr, pretty: true))
          else
            Mix.shell().info(Jason.encode!(reduced, pretty: true))
          end
        _ -> pretty_print(reduced, opts[:top] || 10)
      end

      if opts[:"dry-run"] do
        if Mix.shell().yes?("Enqueue snapshot job with these options?") do
          enqueue(params)
        else
          Mix.shell().info("Dry-run: skipping enqueue")
        end
      end
    else
      enqueue(params)
    end
  end

  defp resolve_print_root(root, repo, wid) do
    cond do
      is_binary(root) -> root
      repo ->
        case Lang.Workspace.Resolver.resolve_root(%{workspace_root: nil, workspace_id: nil, repository: repo}) do
          {:ok, r} -> r
          {:error, reason} -> Mix.raise("Could not resolve repo root: #{inspect(reason)}")
        end
      is_binary(wid) ->
        case Lang.Workspace.Resolver.resolve_root(%{workspace_root: nil, workspace_id: wid, repository: nil}) do
          {:ok, r} -> r
          {:error, reason} -> Mix.raise("Could not resolve workspace root: #{inspect(reason)}")
        end
      true -> Mix.raise("--print requires --root, --repo, or --workspace-id")
    end
  end

  defp enqueue(params) do
    req = %{"jsonrpc" => "2.0", "id" => 1, "method" => "lang.workspace.snapshot", "params" => params}
    case Lang.LSP.DomainRouter.handle(req) do
      %{"error" => err} -> Mix.raise("Snapshot enqueue failed: #{inspect(err)}")
      %{"result" => %{"job_id" => jid}} -> Mix.shell().info("Enqueued snapshot job_id=#{jid}")
      other -> Mix.shell().info("Result: #{inspect(other)}")
    end
  end

  defp parse_repo(nil), do: nil
  defp parse_repo(str) when is_binary(str) do
    case String.split(str, "/") do
      [org, user, ws] -> %{"org" => org, "user" => user, "workspace" => ws}
      _ -> Mix.raise("--repo must be in the form org/user/workspace")
    end
  end

  defp pretty_print(%{kind: "stats_only_by_kind", stats_by_kind: by_kind} = map, top) do
    rows =
      by_kind
      |> Enum.sort_by(fn {_k, v} -> -v[:count] end)
      |> Enum.take(top)
      |> Enum.map(fn {k, %{count: c, bytes: b}} -> {to_string(k), Integer.to_string(c), Integer.to_string(b)} end)

    {wk, wc, wb} =
      Enum.reduce(rows, {4, 5, 5}, fn {k, c, b}, {wk, wc, wb} ->
        {max(wk, String.length(k)), max(wc, String.length(c)), max(wb, String.length(b))}
      end)

    header = String.pad_trailing("kind", wk) <> "  " <> String.pad_leading("count", wc) <> "  " <> String.pad_leading("bytes", wb)
    Mix.shell().info("Stats by kind (total=#{map[:total]}):")
    Mix.shell().info(header)
    rows
    |> Enum.each(fn {k, c, b} ->
      line = String.pad_trailing(k, wk) <> "  " <> String.pad_leading(c, wc) <> "  " <> String.pad_leading(b, wb)
      Mix.shell().info(line)
    end)
  end
  defp pretty_print(%{kind: "stats_only", stats: stats}, _top) do
    Mix.shell().info("Stats:")
    Mix.shell().info(inspect(stats))
  end
  defp pretty_print(%{kind: kind, files: files} = map, top) do
    count = length(files)
    header = "#{kind} files=#{count} (showing up to #{top})"
    Mix.shell().info(header)

    rows =
      files
      |> Enum.take(top)
      |> Enum.map(fn f ->
        path = format_path(f.path)
        size = (f.size || 0) |> Integer.to_string()
        mtime = to_string(f[:mtime] || f["mtime"] || "")
        {path, size, mtime}
      end)

    {wp, ws, wm} =
      Enum.reduce(rows, {4, 4, 4}, fn {p, s, m}, {wp, ws, wm} ->
        {max(wp, String.length(p)), max(ws, String.length(s)), max(wm, String.length(m))}
      end)

    Mix.shell().info(String.pad_trailing("path", wp) <> "  " <> String.pad_leading("size", ws) <> "  " <> String.pad_trailing("mtime", wm))

    Enum.each(rows, fn {p, s, m} ->
      line = String.pad_trailing(p, wp) <> "  " <> String.pad_leading(s, ws) <> "  " <> String.pad_trailing(m, wm)
      Mix.shell().info(line)
    end)

    case map[:stats] || map["stats"] do
      %{} = stats -> Mix.shell().info("totals: " <> inspect(stats))
      _ -> :ok
    end
  end
  defp pretty_print(other, _top), do: Mix.shell().info(inspect(other))

  defp format_path(path) when is_binary(path) do
    maxw = 80
    if String.length(path) > maxw do
      "…" <> String.slice(path, - (maxw - 1), maxw - 1)
    else
      path
    end
  end
  defp format_path(other), do: to_string(other)
end
