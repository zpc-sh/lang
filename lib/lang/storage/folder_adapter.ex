defmodule Lang.Storage.FolderAdapter do
  @moduledoc """
  Adapter that proxies storage operations to Folder APIs.

  Supports:
  - VFS under workspace (team-scoped)
  - OCI registry read (manifest/blob) for CAS AI Memory references (read-only MVP)
  """

  @behaviour Lang.Storage.Adapter
  alias Lang.Storage.URI, as: SURI
  alias Lang.Storage.Config, as: SConfig
  alias Lang.Storage.TokenCache
  require Logger

  @impl true
  def normalize(_root, path_or_uri) do
    case SURI.parse(path_or_uri) do
      {:vfs, info} -> {:ok, {:vfs, info}}
      {:oci, info} -> {:ok, {:oci, info}}
      {:file, _root, rel} -> {:ok, {:vfs_like, rel}}
      {:error, reason} -> {:error, reason}
    end
  end

  # VFS list via Folder API
  @impl true
  def list(_root, path_or_uri, opts \\ []) do
    with {:ok, {:vfs, %{team_id: team_id, workspace_id: wid, path: path}}} <- normalize(nil, path_or_uri) do
      query = %{path: path, depth: Keyword.get(opts, :depth, 1)}
      case Req.get(req(), url: "/api/v1/teams/#{team_id}/workspaces/#{wid}/storage/vfs", params: query) do
        {:ok, %{status: 200, body: %{"data" => list}}} -> {:ok, list}
        {:ok, %{status: 200, body: list}} when is_list(list) -> {:ok, list}
        other -> to_error(other)
      end
    else
      {:ok, {:vfs_like, rel}} -> {:ok, [%{name: rel, uri: rel, kind: :file}]} # minimal fallback
      error -> error
    end
  end

  @impl true
  def stat(_root, path_or_uri) do
    with {:ok, {:vfs, %{team_id: team_id, workspace_id: wid, path: path}}} <- normalize(nil, path_or_uri) do
      case Req.get(req(), url: "/api/v1/teams/#{team_id}/workspaces/#{wid}/storage/vfs", params: %{path: path, depth: 0}) do
        {:ok, %{status: 200, body: %{"data" => [entry | _]}}} -> {:ok, to_stat(entry)}
        {:ok, %{status: 404}} -> {:ok, %{exists: false}}
        other -> to_error(other)
      end
    else
      {:ok, {:oci, _}} -> {:error, :not_implemented}
      error -> error
    end
  end

  @impl true
  def read(_root, path_or_uri, opts \\ []) do
    with {:ok, {:vfs, %{team_id: team_id, workspace_id: wid, path: path}}} <- normalize(nil, path_or_uri) do
      case Req.get(req(receive_timeout: Keyword.get(opts, :timeout, 5_000)), url: "/api/v1/teams/#{team_id}/workspaces/#{wid}/storage/vfs/content", params: %{path: path}) do
        {:ok, %{status: 200, body: %{"data" => %{"content" => content}}}} -> {:ok, content}
        other -> to_error(other)
      end
    else
      {:ok, {:oci, %{owner: owner, repo: repo, reference: ref}}} ->
        registry_get_manifest(owner, repo, ref, opts)
        |> case do
          {:ok, manifest} -> {:ok, Jason.encode!(manifest)}
          error -> error
        end
      error -> error
    end
  end

  @impl true
  def preview(_root, path_or_uri, max_lines \\ 200) do
    with {:ok, {:vfs, %{team_id: team_id, workspace_id: wid, path: path}}} <- normalize(nil, path_or_uri),
         {:ok, content} <- read(nil, "vfs://team/#{team_id}/workspace/#{wid}/" <> path) do
      {:ok, content |> String.split("\n") |> Enum.take(max_lines)}
    else
      {:ok, {:oci, _}} -> {:error, :not_implemented}
      error -> error
    end
  end

  def search(root, pattern, opts \\ []) do
    Lang.Native.FSScanner.search(root, pattern, opts)
  end

  @impl true
  def search_code(root, lang, query, opts \\ []) do
    Lang.Native.FSScanner.search_code(root, lang, query, opts)
  end

  @impl true
  def scan(root, opts \\ []) do
    case Lang.Native.FSScanner.scan(root, opts) do
      {:ok, res} -> {:ok, res}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def write(_root, _path, _content, _mode \\ :replace), do: {:error, :not_implemented}

  @impl true
  def move(_root, _from, _to), do: {:error, :not_implemented}

  @impl true
  def delete(_root, _path, _recursive? \\ false), do: {:error, :not_implemented}

  # Internal helpers
  defp req(opts \\ []) do
    headers =
      case System.get_env("FOLDER_TOKEN") || System.get_env("LANG_DIRUP_TOKEN") do
        nil -> []
        tok -> [{"authorization", "Bearer " <> tok}]
      end

    Req.new()
    |> Req.merge(base_url: System.get_env("FOLDER_URL") || System.get_env("LANG_DIRUP_URL") || "http://127.0.0.1:7070")
    |> Req.merge(put_headers: headers)
    |> Req.merge(opts)
  end

  # Registry helpers (read-only)
  def registry_get_manifest(owner, repo, reference, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    case Lang.Storage.ManifestCache.get(owner, repo, reference) do
      {:ok, manifest} ->
        :telemetry.execute([:lang, :folder, :registry, :manifest], %{}, %{owner: owner, repo: repo, reference: reference, cache: "hit"})
        {:ok, manifest}
      _ -> :miss
    end
    |> case do
      {:ok, manifest} -> {:ok, manifest}
      _ ->
        case Req.get(req(receive_timeout: timeout), url: "/registry/v2/#{owner}/#{repo}/manifests/#{reference}") do
          {:ok, %{status: 200, body: body}} when is_map(body) ->
            _ = Lang.Storage.ManifestCache.put(owner, repo, reference, body)
            :telemetry.execute([:lang, :folder, :registry, :manifest], %{}, %{owner: owner, repo: repo, reference: reference, cache: "miss", auth: "none"})
            {:ok, body}
          {:ok, %{status: 401, headers: headers}} ->
            with {:ok, scope} <- extract_scope(headers),
                 {:ok, token} <- get_or_mint_token(scope),
                 {:ok, resp} <- Req.get(req(receive_timeout: timeout) |> with_token(token), url: "/registry/v2/#{owner}/#{repo}/manifests/#{reference}") do
              case resp do
                %{status: 200, body: body} when is_map(body) ->
                  _ = Lang.Storage.ManifestCache.put(owner, repo, reference, body)
                  :telemetry.execute([:lang, :folder, :registry, :manifest], %{}, %{owner: owner, repo: repo, reference: reference, cache: "miss", auth: "jwt"})
                  {:ok, body}
                _ -> to_error({:ok, resp})
              end
            else
              _ -> {:error, {:auth_required, parse_www_authenticate(headers)}}
            end
          other -> to_error(other)
        end
    end
  end

  def registry_get_blob(owner, repo, digest, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    force_inline = Keyword.get(opts, :force_inline, false) || SConfig.force_inline_binaries?()
    inline_cap = SConfig.inline_text_max_bytes()

    # Do not auto-follow to detect 307 and return URI
    case Req.get(req(receive_timeout: timeout) |> Req.merge(follow_redirects: false), url: "/registry/v2/#{owner}/#{repo}/blobs/#{digest}") do
      {:ok, %{status: 307, headers: headers}} ->
        uri = get_location(headers)
        :telemetry.execute([:lang, :folder, :registry, :blob], %{}, %{owner: owner, repo: repo, digest: digest, strategy: "redirect"})
        {:ok, %{uri: uri}}

      {:ok, %{status: 200, body: body, headers: headers}} ->
        {ctype, clen} = {get_ct(headers), get_len(headers)}
        cond do
          force_inline and is_binary(body) and byte_size(body) <= inline_cap ->
            :telemetry.execute([:lang, :folder, :registry, :blob], %{}, %{owner: owner, repo: repo, digest: digest, strategy: "inline", mediaType: ctype, size: byte_size(body)})
            {:ok, %{content: body, mediaType: ctype, size: byte_size(body)}}
          text_like?(ctype) and is_binary(body) and byte_size(body) <= inline_cap ->
            :telemetry.execute([:lang, :folder, :registry, :blob], %{}, %{owner: owner, repo: repo, digest: digest, strategy: "inline", mediaType: ctype, size: byte_size(body)})
            {:ok, %{content: body, mediaType: ctype, size: byte_size(body)}}
          true ->
            :telemetry.execute([:lang, :folder, :registry, :blob], %{}, %{owner: owner, repo: repo, digest: digest, strategy: "uri", mediaType: ctype, size: clen})
            {:ok, %{uri: "/registry/v2/#{owner}/#{repo}/blobs/#{digest}", mediaType: ctype, size: clen}}
        end
      {:ok, %{status: 401, headers: headers}} ->
        with {:ok, scope} <- extract_scope(headers),
             {:ok, token} <- get_or_mint_token(scope),
             {:ok, resp} <- Req.get(req(receive_timeout: timeout) |> Req.merge(follow_redirects: false) |> with_token(token), url: "/registry/v2/#{owner}/#{repo}/blobs/#{digest}") do
          case resp do
            %{status: 307, headers: hdrs} ->
              :telemetry.execute([:lang, :folder, :registry, :blob], %{}, %{owner: owner, repo: repo, digest: digest, strategy: "redirect"})
              {:ok, %{uri: get_location(hdrs)}}
            %{status: 200, body: body, headers: hdrs} ->
              {ctype, clen} = {get_ct(hdrs), get_len(hdrs)}
              cond do
                force_inline and is_binary(body) and byte_size(body) <= inline_cap ->
                  :telemetry.execute([:lang, :folder, :registry, :blob], %{}, %{owner: owner, repo: repo, digest: digest, strategy: "inline", mediaType: ctype, size: byte_size(body)})
                  {:ok, %{content: body, mediaType: ctype, size: byte_size(body)}}
                text_like?(ctype) and is_binary(body) and byte_size(body) <= inline_cap ->
                  :telemetry.execute([:lang, :folder, :registry, :blob], %{}, %{owner: owner, repo: repo, digest: digest, strategy: "inline", mediaType: ctype, size: byte_size(body)})
                  {:ok, %{content: body, mediaType: ctype, size: byte_size(body)}}
                true ->
                  :telemetry.execute([:lang, :folder, :registry, :blob], %{}, %{owner: owner, repo: repo, digest: digest, strategy: "uri", mediaType: ctype, size: clen})
                  {:ok, %{uri: "/registry/v2/#{owner}/#{repo}/blobs/#{digest}", mediaType: ctype, size: clen}}
              end
            _ -> to_error({:ok, resp})
          end
        else
          _ -> {:error, {:auth_required, parse_www_authenticate(headers)}}
        end
      other -> to_error(other)
    end
  end

  defp get_location(headers) do
    headers |> Enum.find_value(fn {k, v} -> String.downcase(k) == "location" and v end)
  end

  defp get_ct(headers) do
    headers |> Enum.find_value(fn {k, v} -> String.downcase(k) == "content-type" and v end)
  end

  defp get_len(headers) do
    case Enum.find_value(headers, fn {k, v} -> String.downcase(k) == "content-length" and v end) do
      nil -> nil
      v ->
        case Integer.parse(v) do
          {i, _} -> i
          _ -> nil
        end
    end
  end

  defp text_like?(nil), do: false
  defp text_like?(ct), do: String.starts_with?(ct, "text/") or String.contains?(ct, ["json", "yaml", "ld+json"])

  defp parse_www_authenticate(headers) do
    case Enum.find(headers, fn {k, _} -> String.downcase(k) == "www-authenticate" end) do
      {_, v} -> v
      _ -> nil
    end
  end

  defp extract_scope(headers) do
    case parse_www_authenticate(headers) do
      nil -> {:error, :no_challenge}
      challenge ->
        # crude parse: scope="..."
        case Regex.run(~r/scope="([^"]+)"/, challenge) do
          [_, scope] -> {:ok, scope}
          _ -> {:error, :no_scope}
        end
    end
  end

  defp get_or_mint_token(scope) do
    case TokenCache.get(scope) do
      {:ok, token} -> {:ok, token}
      _ ->
        case mint_token(scope) do
          {:ok, %{access_token: tok, expires_in: exp}} ->
            _ = TokenCache.put(scope, tok, exp)
            {:ok, tok}
          other -> other
        end
    end
  end

  defp mint_token(scope) do
    form = {:form, [
      {"grant_type", "client_credentials"},
      {"scope", scope},
      {"audience", System.get_env("FOLDER_AUDIENCE") || "registry.folder.sh"}
    ]}

    case Req.post(req(), url: "/api/v1/auth/token", body: form) do
      {:ok, %{status: 200, body: %{"access_token" => tok, "expires_in" => exp} = body}} ->
        {:ok, %{access_token: tok, expires_in: exp || body["expires_in"] || 900}}
      {:ok, %{status: st, body: body}} -> {:error, {:http_status, st, body}}
      {:error, e} -> {:error, {:http_error, e}}
    end
  end

  defp with_token(req, token) do
    Req.merge(req, put_headers: [{"authorization", "Bearer " <> token}])
  end

  defp to_error({:ok, %{status: status, body: body}}), do: {:error, {:http_status, status, body}}
  defp to_error({:error, e}), do: {:error, {:http_error, e}}
  defp to_error(other), do: {:error, {:unexpected, other}}

  defp to_stat(entry) when is_map(entry) do
    %{
      exists: true,
      kind: (case entry["kind"] || entry[:kind] do "directory" -> :directory; _ -> :file end),
      size: entry["size"] || entry[:size],
      mtime: entry["mtime"] || entry[:mtime]
    }
  end
end
