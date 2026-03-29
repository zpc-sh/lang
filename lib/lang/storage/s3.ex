defmodule Lang.Storage.S3 do
  @moduledoc """
  Minimal S3 helpers for large, LANG-specific analysis artifacts.

  Use Kyozo for long-term/storage-heavy data; this is for LANG-owned
  artifacts like snapshots, large analysis results, and pattern libraries.
  """

  alias ExAws.S3

  def bucket do
    Application.get_env(:lang, :s3_bucket) || System.get_env("S3_BUCKET") || ""
  end

  def put_object(key, binary, headers \\ []) when is_binary(key) and is_binary(binary) do
    case bucket() do
      "" -> {:error, :missing_bucket}
      b -> S3.put_object(b, key, binary, headers) |> ExAws.request()
    end
  end

  def get_object(key) when is_binary(key) do
    case bucket() do
      "" -> {:error, :missing_bucket}
      b -> S3.get_object(b, key) |> ExAws.request()
    end
  end

  def presign_get(key, expires_in \\ 900) do
    case bucket() do
      "" -> {:error, :missing_bucket}
      b -> S3.presigned_url(ExAws.Config.new(:s3), :get, b, key, expires_in: expires_in)
    end
  end

  def presign_put(key, headers \\ [], expires_in \\ 900) do
    case bucket() do
      "" ->
        {:error, :missing_bucket}

      b ->
        S3.presigned_url(ExAws.Config.new(:s3), :put, b, key,
          expires_in: expires_in,
          headers: headers
        )
    end
  end

  @doc """
  List objects under a prefix. Returns {:ok, [%{key:, size:, last_modified:}]}
  """
  def list_objects(prefix, opts \\ []) when is_binary(prefix) do
    case bucket() do
      "" ->
        {:error, :missing_bucket}

      b ->
        max_keys = Keyword.get(opts, :max_keys, 1000)
        req = S3.list_objects_v2(b, prefix: prefix, max_keys: max_keys)

        with {:ok, %{"Contents" => contents}} <- ExAws.request(req) do
          objs =
            Enum.map(List.wrap(contents), fn m ->
              %{
                key: m["Key"],
                size: m["Size"],
                last_modified: m["LastModified"]
              }
            end)

          {:ok, objs}
        end
    end
  end
end
