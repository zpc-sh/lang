defmodule Mix.Tasks.Spec.Apply do
  use Mix.Task
  @shortdoc "Apply proposal patch.json attachments from messages to target files"
  @moduledoc """
  Usage:
    mix spec.apply --id <request_id> [--source inbox|outbox] [--target /path/to/target/repo]

  Scans messages of type "proposal" under the chosen source (default: inbox),
  finds attachments named `patch.json`, and applies JSON Pointer operations
  (add/replace/remove) to the referenced file(s).

  Patch format (either inline file or via message ref):
  {
    "file": "relative/path.json",         # optional; falls back to message.ref.path
    "base_pointer": "/api",               # optional; falls back to message.ref.json_pointer
    "ops": [
      {"op": "replace", "path": "/hash", "value": "..."},
      {"op": "add",     "path": "/foo/bar", "value": 1},
      {"op": "remove",  "path": "/old"}
    ]
  }
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string, source: :string, target: :string])
    id = req!(opts, :id)
    source = Keyword.get(opts, :source, "inbox")
    target_root = Keyword.get(opts, :target, File.cwd!())

    req_root = Path.join(["work", "spec_requests", id])
    src_dir = Path.join(req_root, source)
    File.dir?(src_dir) || Mix.raise("Source not found: #{src_dir}")

    messages = Path.wildcard(Path.join(src_dir, "msg_*.json"))
    |> Enum.map(&{&1, Jason.decode!(File.read!(&1))})
    |> Enum.filter(fn {_p, m} -> m["type"] == "proposal" end)

    if messages == [] do
      Mix.shell().info("No proposal messages found in #{src_dir}")
      :ok
    else
      Enum.each(messages, fn {msg_path, msg} ->
        (msg["attachments"] || [])
        |> Enum.filter(&String.ends_with?(&1, "patch.json"))
        |> Enum.each(fn rel ->
          patch_path = Path.join(req_root, rel)
          apply_patch!(patch_path, msg, target_root)
          Mix.shell().info("Applied patch from #{rel} (msg #{Path.basename(msg_path)})")
        end)
      end)
    end
  end

  defp apply_patch!(patch_path, msg, target_root) do
    patch = Jason.decode!(File.read!(patch_path))
    file_rel = patch["file"] || get_in(msg, ["ref", "path"]) || Mix.raise("Patch missing file and message.ref.path")
    base_ptr = patch["base_pointer"] || get_in(msg, ["ref", "json_pointer"]) || ""
    ops = patch["ops"] || Mix.raise("Patch missing ops")

    target_path = Path.join(target_root, file_rel)
    content = File.read!(target_path)
    json = Jason.decode!(content)

    final = Enum.reduce(ops, json, fn op, acc -> apply_op!(acc, base_ptr, op) end)
    File.write!(target_path, Jason.encode_to_iodata!(final, pretty: true))
  end

  defp apply_op!(doc, base, %{"op" => op, "path" => path} = o) do
    ptr = normalize_ptr(base, path)
    case op do
      "add" -> json_put(doc, ptr, Map.fetch!(o, "value"), :add)
      "replace" -> json_put(doc, ptr, Map.fetch!(o, "value"), :replace)
      "remove" -> json_remove(doc, ptr)
      other -> Mix.raise("Unsupported op: #{inspect(other)}")
    end
  end

  defp normalize_ptr("", p), do: p
    
  defp normalize_ptr(nil, p), do: p
  defp normalize_ptr(base, p) do
    base = if base == "/", do: "", else: base
    p = if String.starts_with?(p, "/"), do: p, else: "/" <> p
    base <> p
  end

  # JSON Pointer utilities (very small subset)
  defp json_put(doc, path, value, mode) when is_binary(path) do
    tokens = pointer_tokens(path)
    put_in_pointer(doc, tokens, value, mode)
  end

  defp json_remove(doc, path) do
    tokens = pointer_tokens(path)
    remove_in_pointer(doc, tokens)
  end

  defp pointer_tokens(""), do: []
  defp pointer_tokens("/"), do: []
  defp pointer_tokens(path) do
    path
    |> String.trim_leading("/")
    |> String.split("/", trim: true)
    |> Enum.map(&String.replace(&1, ["~1", "~0"], fn "~1" -> "/"; "~0" -> "~" end))
    |> Enum.map(&decode_index/1)
  end

  defp decode_index(seg) do
    case Integer.parse(seg) do
      {i, ""} -> {:idx, i}
      _ -> {:key, seg}
    end
  end

  defp put_in_pointer(doc, [], _val, _mode), do: doc
  defp put_in_pointer(doc, [{:key, k}], val, :replace) when is_map(doc), do: Map.put(doc, k, val)
  defp put_in_pointer(doc, [{:key, k}], val, :add) when is_map(doc), do: Map.put(doc, k, val)
  defp put_in_pointer(list, [{:idx, i}], val, mode) when is_list(list) do
    cond do
      mode == :replace and i < length(list) -> List.replace_at(list, i, val)
      mode == :add and i == length(list) -> list ++ [val]
      mode == :add and i < length(list) -> List.insert_at(list, i, val)
      true -> Mix.raise("Invalid list index #{i} for mode #{mode}")
    end
  end
  defp put_in_pointer(doc, [{:key, k} | rest], val, mode) when is_map(doc) do
    child = Map.get(doc, k, default_for(rest))
    Map.put(doc, k, put_in_pointer(child, rest, val, mode))
  end
  defp put_in_pointer(list, [{:idx, i} | rest], val, mode) when is_list(list) do
    ensure = if i < length(list), do: Enum.at(list, i), else: default_for(rest)
    updated = put_in_pointer(ensure, rest, val, mode)
    cond do
      i < length(list) -> List.replace_at(list, i, updated)
      i == length(list) -> list ++ [updated]
      true -> Mix.raise("Invalid list index #{i}")
    end
  end
  defp put_in_pointer(_other, _rest, _val, _mode), do: Mix.raise("Unsupported structure for pointer")

  defp remove_in_pointer(doc, [{:key, k}]) when is_map(doc), do: Map.delete(doc, k)
  defp remove_in_pointer(list, [{:idx, i}]) when is_list(list) and i < length(list), do: List.delete_at(list, i)
  defp remove_in_pointer(doc, [{:key, k} | rest]) when is_map(doc) do
    case Map.fetch(doc, k) do
      {:ok, v} -> Map.put(doc, k, remove_in_pointer(v, rest))
      :error -> doc
    end
  end
  defp remove_in_pointer(list, [{:idx, i} | rest]) when is_list(list) and i < length(list) do
    v = Enum.at(list, i)
    List.replace_at(list, i, remove_in_pointer(v, rest))
  end
  defp remove_in_pointer(other, _), do: other

  defp default_for([{:idx, _} | _]), do: []
  defp default_for([{:key, _} | _]), do: %{}

  defp req!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
end
