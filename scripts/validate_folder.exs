Mix.install([
  {:req, "~> 0.4"}
])

defmodule ValidateFolder do
  @moduledoc "Simple Folder rollout smoke tests using Req."

  def run do
    base = env!("FOLDER_URL", "http://127.0.0.1:7070")
    owner = System.get_env("FOLDER_OWNER")
    repo = System.get_env("FOLDER_REPO")
    ref = System.get_env("FOLDER_REFERENCE") || "latest"
    digest = System.get_env("FOLDER_DIGEST")
    token = System.get_env("FOLDER_TOKEN")

    IO.puts("→ Handshake /registry/v2")
    req() |> Req.get!(url: base <> "/registry/v2") |> tap(&print_status/1)

    if owner && repo do
      IO.puts("→ Manifest #{owner}/#{repo}@#{ref}")
      case get_manifest(base, owner, repo, ref, token) do
        {:ok, body} -> IO.puts("   manifest OK, layers=#{length(body["layers"] || [])}")
        {:error, {:auth_required, ch}} -> IO.puts("   AUTH REQUIRED: #{inspect(ch)}")
        other -> IO.puts("   manifest error: #{inspect(other)}")
      end
    else
      IO.puts("! Skip manifest (set FOLDER_OWNER/FOLDER_REPO)")
    end

    if owner && repo && digest do
      IO.puts("→ Blob #{owner}/#{repo}@#{digest}")
      case get_blob(base, owner, repo, digest, token) do
        {:ok, %{uri: uri}} -> IO.puts("   307 -> #{uri}")
        {:ok, %{content: _bin, mediaType: ct, size: sz}} -> IO.puts("   inline #{ct} bytes=#{sz}")
        {:error, {:auth_required, ch}} -> IO.puts("   AUTH REQUIRED: #{inspect(ch)}")
        other -> IO.puts("   blob error: #{inspect(other)}")
      end
    else
      IO.puts("! Skip blob (set FOLDER_OWNER/FOLDER_REPO/FOLDER_DIGEST)")
    end

    team = System.get_env("FOLDER_TEAM_ID")
    wid = System.get_env("FOLDER_WORKSPACE_ID")
    path = System.get_env("FOLDER_PATH") || "."

    if team && wid do
      IO.puts("→ VFS list files (team/workspace)")
      url = base <> "/api/v1/teams/#{team}/workspaces/#{wid}/files"
      req() |> Req.get!(url: url) |> tap(&print_status/1)

      IO.puts("→ VFS read content (path)")
      url2 = base <> "/api/v1/teams/#{team}/workspaces/#{wid}/files?path=#{URI.encode(path)}"
      req() |> Req.get!(url: url2) |> tap(&print_status/1)
    else
      IO.puts("! Skip VFS (set FOLDER_TEAM_ID/FOLDER_WORKSPACE_ID)")
    end
  end

  defp req do
    headers =
      case System.get_env("FOLDER_TOKEN") do
        nil -> []
        tok -> [{"authorization", "Bearer " <> tok}]
      end

    Req.new()
    |> Req.merge(put_headers: headers)
    |> Req.merge(redirect_trusted: false)
    |> Req.merge(receive_timeout: 5_000)
  end

  defp get_manifest(base, owner, repo, ref, pat) do
    r = req() |> Req.get(url: base <> "/registry/v2/#{owner}/#{repo}/manifests/#{ref}")
    case r do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: 401, headers: hdrs}} -> {:error, {:auth_required, www(hdrs)}}
      other -> other
    end
  end

  defp get_blob(base, owner, repo, digest, pat) do
    r = req() |> Req.get(url: base <> "/registry/v2/#{owner}/#{repo}/blobs/#{digest}", follow_redirects: false)
    case r do
      {:ok, %{status: 307, headers: hdrs}} -> {:ok, %{uri: loc(hdrs)}}
      {:ok, %{status: 200, headers: hdrs, body: body}} -> {:ok, %{content: body, mediaType: ct(hdrs), size: byte_size(body)}}
      {:ok, %{status: 401, headers: hdrs}} -> {:error, {:auth_required, www(hdrs)}}
      other -> other
    end
  end

  defp ct(hdrs), do: find(hdrs, "content-type")
  defp loc(hdrs), do: find(hdrs, "location")
  defp www(hdrs), do: find(hdrs, "www-authenticate")
  defp find(hdrs, key), do: Enum.find_value(hdrs, fn {k, v} -> String.downcase(k) == key and v end)

  defp print_status(%{status: st} = resp), do: IO.puts("   status=#{st}")
end

ValidateFolder.run()
