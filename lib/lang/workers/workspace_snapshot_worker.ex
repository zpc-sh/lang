defmodule Lang.Workers.WorkspaceSnapshotWorker do
  @moduledoc """
  Snapshot a workspace filesystem tree and store it in S3 (gzipped JSON).

  Args:
  - "workspace_root": absolute path to workspace root
  - "repository": %{org, user, workspace} (optional, used for S3 key layout)
  - "org_id": organization id (optional)
  - "max_depth": integer (default 12)
  - "key": optional S3 key override
  """

  use Oban.Worker, queue: :analysis, max_attempts: 3
  require Logger

  @impl true
  def perform(%Oban.Job{args: args}) do
    root = args["workspace_root"]
    max_depth = args["max_depth"] || 12
    repo = args["repository"] || %{}
    key = args["key"] || default_key(repo)
    reduce = args["reduce"] || "manifest_only"
    max_files = args["max_files"] || 5_000
    max_total_size = args["max_total_size"] || :infinity
    include_globs = List.wrap(args["include_globs"] || [])
    exclude_globs = List.wrap(args["exclude_globs"] || [])

    with {:ok, scan} <- Lang.Native.FSScanner.scan(root, max_depth: max_depth),
         {:ok, reduced} <- maybe_reduce(scan, reduce, max_files, include_globs, exclude_globs, max_total_size),
         {:ok, payload} <- encode_payload(root, reduced),
         {:ok, _} <- put_s3(key, payload) do
      Logger.info("workspace snapshot stored", key: key, root: root)
      :ok
    else
      {:error, reason} ->
        Logger.error("workspace snapshot failed", reason: inspect(reason), root: root)
        {:error, reason}
    end
  end

  @doc """
  Convenience API: scan and reduce a workspace root according to options.

  Options:
  - :max_depth (default 12)
  - :reduce (default "manifest_only")
  - :max_files (default 5_000)
  - :include_globs (default [])
  - :exclude_globs (default [])
  - :max_total_size (default :infinity)
  """
  @spec scan_and_reduce(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def scan_and_reduce(root, opts \\ []) when is_binary(root) do
    max_depth = Keyword.get(opts, :max_depth, 12)
    reduce = Keyword.get(opts, :reduce, "manifest_only")
    max_files = Keyword.get(opts, :max_files, 5_000)
    include_globs = Keyword.get(opts, :include_globs, [])
    exclude_globs = Keyword.get(opts, :exclude_globs, [])
    max_total_size = Keyword.get(opts, :max_total_size, :infinity)

    with {:ok, scan} <- Lang.Native.FSScanner.scan(root, max_depth: max_depth),
         {:ok, reduced} <- maybe_reduce(scan, reduce, max_files, include_globs, exclude_globs, max_total_size) do
      {:ok, reduced}
    end
  end

  defp encode_payload(root, content) do
    data = %{
      version: 1,
      captured_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      root: root,
      snapshot: content
    }

    try do
      json = Jason.encode!(data)
      {:ok, :zlib.gzip(json)}
    rescue
      e -> {:error, {:encode_failed, e}}
    end
  end

  defp maybe_reduce(scan, "manifest_only", max_files, inc, exc, max_total_size) do
    {:ok, %{
      kind: "manifest",
      stats: extract_field(scan, [:stats]),
      files: build_manifest(extract_field(scan, [:tree]), max_files, inc, exc, max_total_size)
    }}
  end
  defp maybe_reduce(scan, "with_previews", max_files, inc, exc, max_total_size) do
    files = build_manifest(extract_field(scan, [:tree]), max_files, inc, exc, max_total_size)
    previews =
      files
      |> Enum.take(10)
      |> Enum.map(fn f ->
        case Lang.Native.FSScanner.preview(f.path, max_lines: 50) do
          {:ok, lines} when is_list(lines) -> Map.put(f, :preview, Enum.join(lines, "\n"))
          {:ok, bin} when is_binary(bin) -> Map.put(f, :preview, bin)
          _ -> f
        end
      end)

    {:ok, %{
      kind: "manifest_with_previews",
      stats: extract_field(scan, [:stats]),
      files: previews ++ Enum.drop(files, 10)
    }}
  end
  defp maybe_reduce(scan, "stats_only", _max_files, _inc, _exc) do
    {:ok, %{kind: "stats_only", stats: extract_field(scan, [:stats])}}
  end
  defp maybe_reduce(scan, "stats_only_by_kind", _max_files, _inc, _exc, _max_total_size) do
    files = build_manifest(extract_field(scan, [:tree]), 10_000, [], [], :infinity)
    by_kind =
      files
      |> Enum.reduce(%{}, fn f, acc ->
        k = file_kind_from_path(f.path) || (f.kind |> to_string())
        {count, bytes} = Map.get(acc, k, {0, 0})
        Map.put(acc, k, {count + 1, bytes + (f.size || 0)})
      end)
      |> Enum.into(%{}, fn {k, {c, b}} -> {k, %{count: c, bytes: b}} end)
    {:ok, %{kind: "stats_only_by_kind", stats_by_kind: by_kind, total: length(files)}}
  end
  defp maybe_reduce(scan, _other, _max_files, _inc, _exc, _max_total_size), do: {:ok, scan}

  defp extract_field(map, [key]) do
    cond do
      is_map(map) and Map.has_key?(map, key) -> Map.get(map, key)
      is_map(map) and Map.has_key?(map, to_string(key)) -> Map.get(map, to_string(key))
      true -> nil
    end
  end

  defp build_manifest(nil, _max, _inc, _exc, _max_total_size), do: []
  defp build_manifest(tree, max, inc, exc, max_total_size) do
    files =
      tree
      |> collect_files([])
      |> maybe_filter_globs(inc, exc)
      |> Enum.sort_by(& &1.path)

    files
    |> take_with_total_size(max, max_total_size)
  end

  defp collect_files(%{} = node, acc) do
    kind = (node[:kind] || node["kind"])
    path = node[:path] || node["path"] || node[:uri] || node["uri"] || node[:name] || node["name"]
    size = node[:size] || node["size"]
    mtime = node[:mtime] || node["mtime"]
    children = node[:children] || node["children"] || []

    acc =
      case kind do
        :directory -> acc
        "directory" -> acc
        _ ->
          if is_binary(path) do
            [%{path: path, kind: kind || "file", size: size, mtime: mtime} | acc]
          else
            acc
          end
      end

    Enum.reduce(List.wrap(children), acc, fn ch, a -> collect_files(ch, a) end)
  end
  defp collect_files(list, acc) when is_list(list), do: Enum.reduce(list, acc, fn n, a -> collect_files(n, a) end)

  defp take_with_total_size(files, max_count, :infinity) do
    Enum.take(files, max_count)
  end
  defp take_with_total_size(files, max_count, max_total_size) when is_integer(max_total_size) do
    {picked, _bytes} =
      Enum.reduce_while(files, {[], 0}, fn f, {acc, total} ->
        size = f.size || 0
        cond do
          length(acc) >= max_count -> {:halt, {acc, total}}
          total + size > max_total_size -> {:halt, {acc, total}}
          true -> {:cont, {[f | acc], total + size}}
        end
      end)
    Enum.reverse(picked)
  end

  defp file_kind_from_path(path) when is_binary(path) do
    ext = Path.extname(path)
    if ext == "", do: "other", else: String.trim_leading(ext, ".")
  end

  defp maybe_filter_globs(files, [], []), do: files
  defp maybe_filter_globs(files, inc, exc) do
    Enum.filter(files, fn %{path: path} ->
      include_ok = if inc == [], do: true, else: Enum.any?(inc, &glob_match?(path, &1))
      exclude_ok = not Enum.any?(exc, &glob_match?(path, &1))
      include_ok and exclude_ok
    end)
  end

  defp glob_match?(path, pattern) when is_binary(path) and is_binary(pattern) do
    # Simple glob: * → .*, ? → . , escape other regex chars
    regex =
      pattern
      |> Regex.escape()
      |> String.replace("\\*", ".*")
      |> String.replace("\\?", ".")
      |> then(&Regex.compile!("^" <> &1 <> "$"))

    Regex.match?(regex, path)
  end

  defp put_s3(key, binary) do
    case Lang.Storage.S3.put_object(key, binary, [{"content-encoding", "gzip"}, {"content-type", "application/json"}]) do
      {:ok, _} -> {:ok, :stored}
      {:error, reason} -> {:error, {:s3_put_failed, reason}}
    end
  end

  defp default_key(%{"org" => org, "user" => user, "workspace" => ws}) when is_binary(org) and is_binary(user) and is_binary(ws) do
    ts = DateTime.utc_now() |> DateTime.to_unix(:second)
    "org/#{org}/user/#{user}/workspaces/#{ws}/snapshots/#{ts}.json.gz"
  end
  defp default_key(_), do: "snapshots/#{DateTime.utc_now() |> DateTime.to_unix(:second)}.json.gz"
end
