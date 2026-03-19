defmodule Lang.Storage.VFS do
  @moduledoc """
  Integration shim for content-addressed storage (Kyozo VFS).

  For now, we return a deterministic URI based on SHA256 of content.
  Replace `put/1` and `head/1` with calls into kyozo_core when available.
  """

  @behaviour __MODULE__

  @callback put(binary()) :: String.t()
  @callback head(String.t()) :: {:ok, map()} | {:error, term()}
  @callback get(String.t()) :: {:ok, binary()} | {:error, term()}

  @impl true
  def put(content) when is_binary(content) do
    # Prefer Kyozo Core storage if available
    cond do
      Code.ensure_loaded?(Kyozo.Storage) and function_exported?(Kyozo.Storage, :put, 1) ->
        Kyozo.Storage.put(content)

      true ->
        hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
        "vfs://sha256/" <> hash
    end
  end

  @impl true
  def head(uri) do
    cond do
      Code.ensure_loaded?(Kyozo.Storage) and function_exported?(Kyozo.Storage, :head, 1) ->
        Kyozo.Storage.head(uri)

      is_binary(uri) and String.starts_with?(uri, "vfs://sha256/") ->
        {:ok, %{algo: :sha256, hash: String.replace_prefix(uri, "vfs://sha256/", "")}}

      true ->
        {:error, :unsupported_uri}
    end
  end

  @impl true
  def get(uri) do
    cond do
      Code.ensure_loaded?(Kyozo.Storage) and function_exported?(Kyozo.Storage, :get, 1) ->
        Kyozo.Storage.get(uri)

      true ->
        {:error, :not_available}
    end
  end
end
