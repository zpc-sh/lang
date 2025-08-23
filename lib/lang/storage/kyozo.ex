defmodule Lang.Storage.Kyozo do
  @moduledoc """
  Thin client for Kyozo VFS Content-Addressable Storage (CAS).

  Notes:
  - Uses Req for HTTP per project guidelines.
  - LANG never holds cloud creds; Kyozo issues presigned URLs.
  - All functions are safe, short-lived calls (no blocking processes).
  """

  require Logger

  @type object_id :: String.t()
  @type uri :: String.t()

  @doc """
  Create a new object placeholder and receive an upload URL.

  Returns {:ok, %{object_id, upload_url}}.
  """
  @spec create_object(map()) :: {:ok, map()} | {:error, term()}
  def create_object(metadata) when is_map(metadata) do
    post("/v1/objects", metadata)
  end

  @doc """
  Mark an object upload as complete.
  """
  @spec complete_upload(object_id()) :: :ok | {:error, term()}
  def complete_upload(object_id) when is_binary(object_id) do
    case post("/v1/objects/#{object_id}/complete", %{}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieve a presigned download URL for an object.
  """
  @spec presign_download(object_id()) :: {:ok, String.t()} | {:error, term()}
  def presign_download(object_id) when is_binary(object_id) do
    with {:ok, %{"url" => url}} <- get("/v1/objects/#{object_id}/download") do
      {:ok, url}
    end
  end

  @doc """
  Get object head/metadata.
  """
  @spec head(object_id()) :: {:ok, map()} | {:error, :not_found | term()}
  def head(object_id) when is_binary(object_id) do
    case get("/v1/objects/#{object_id}") do
      {:ok, meta} -> {:ok, meta}
      {:error, %Req.Response{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # Internal HTTP helpers
  defp base_url do
    Application.get_env(:lang, :kyozo_base_url) || System.get_env("KYOZO_URL") || "http://localhost:4100"
  end

  defp get(path) do
    request(:get, path, nil)
  end

  defp post(path, body) do
    request(:post, path, body)
  end

  defp request(method, path, body) do
    url = base_url() <> path

    opts = [
      url: url,
      method: method,
      json: body,
      headers: default_headers(),
      receive_timeout: 15_000
    ]

    case Req.request(opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body} = resp} ->
        Logger.warning("Kyozo request failed", url: url, status: status, body: body)
        {:error, resp}

      {:error, reason} ->
        Logger.error("Kyozo request error", url: url, reason: reason)
        {:error, reason}
    end
  end

  defp default_headers do
    token = Application.get_env(:lang, :kyozo_api_token) || System.get_env("KYOZO_API_TOKEN")
    headers = [{"content-type", "application/json"}]
    if token, do: headers ++ [{"authorization", "Bearer #{token}"}], else: headers
  end
end

