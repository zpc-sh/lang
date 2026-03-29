defmodule Mix.Tasks.Folder.Toc.Preview do
  use Mix.Task
  @shortdoc "Resolve a TOC path from an OCI memory manifest and preview or return blob URI"

  @moduledoc """
  Resolve a file-like path via the TOC layer in a Folder AI Memory manifest, then preview its content
  if text-sized or print a blob URI if large/binary.

      mix folder.toc.preview OWNER REPO REFERENCE PATH

  Examples:

      mix folder.toc.preview acme ai/memory/foundation latest memory/foundation/patterns.md

  Requirements:
  - FOLDER_URL env pointing to Folder base (e.g. http://127.0.0.1:7070)
  - PAT or token via FOLDER_TOKEN (for direct access) or token mint enabled at /api/v1/auth/token

  Notes:
  - Uses Lang.Storage.FolderAdapter registry helpers directly (no billing gate)
  - Obeys inline caps and 307 redirect behavior inside the adapter
  """

  @toc_mt "application/vnd.folder.ai.toc.v1+json"

  @impl true
  def run([owner, repo, reference, path]) do
    Mix.shell().info("Resolving TOC path: #{path} from #{owner}/#{repo}@#{reference}")
    adapter = Application.get_env(:lang, :storage_adapter, Lang.Storage.LocalFS)

    unless function_exported?(adapter, :registry_get_manifest, 4) do
      Mix.raise("Current storage adapter does not support registry operations: #{inspect(adapter)}")
    end

    with {:ok, manifest} <- adapter.registry_get_manifest(owner, repo, reference, []),
         {:ok, toc_digest} <- toc_digest(manifest),
         {:ok, toc_json} <- fetch_toc(adapter, owner, repo, toc_digest),
         {:ok, entry} <- lookup_entry(toc_json, path),
         {:ok, out} <- adapter.registry_get_blob(owner, repo, Map.fetch!(entry, "digest"), force_inline: true) do
      case out do
        %{content: bin} ->
          preview = String.slice(bin, 0, Lang.Storage.Config.preview_max_bytes())
          Mix.shell().info("\n=== Content (truncated if large) ===\n" <> preview)
        %{uri: uri} ->
          Mix.shell().info("Blob URI (binary or large): #{uri}")
      end
    else
      {:error, {:auth_required, ch}} ->
        Mix.raise("Auth required (WWW-Authenticate): #{inspect(ch)}")
      {:error, :toc_missing} ->
        Mix.raise("TOC layer missing in manifest")
      {:error, {:not_found, p}} ->
        Mix.raise("Path not found in TOC: #{p}")
      {:error, other} ->
        Mix.raise("Error: #{inspect(other)}")
    end
  end

  def run(_), do: Mix.raise("usage: mix folder.toc.preview OWNER REPO REFERENCE PATH")

  defp toc_digest(%{"layers" => layers}) when is_list(layers) do
    case Enum.find(layers, fn l -> (l["mediaType"] || l[:mediaType]) == @toc_mt end) do
      %{"digest" => d} -> {:ok, d}
      %{digest: d} -> {:ok, d}
      _ -> {:error, :toc_missing}
    end
  end
  defp toc_digest(_), do: {:error, :toc_missing}

  defp fetch_toc(adapter, owner, repo, digest) do
    case adapter.registry_get_blob(owner, repo, digest, force_inline: true) do
      {:ok, %{content: bin}} ->
        case Jason.decode(bin) do
          {:ok, json} -> {:ok, json}
          err -> err
        end
      {:ok, %{uri: uri}} -> {:error, {:toc_blob_redirected, uri}}
      other -> other
    end
  end

  defp lookup_entry(%{"entries" => entries}, path) when is_list(entries) do
    case Enum.find(entries, fn e -> e["path"] == path end) do
      nil -> {:error, {:not_found, path}}
      e -> {:ok, e}
    end
  end
  defp lookup_entry(_, path), do: {:error, {:not_found, path}}
end

