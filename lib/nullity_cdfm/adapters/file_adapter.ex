defmodule Nullity.CDFM.Adapters.FileAdapter do
  @moduledoc """
  Behaviour for abstracting file I/O. Implementations can use native NIFs
  (preferred) or standard Elixir for tests.
  """

  @callback read(path :: String.t()) :: {:ok, binary()} | {:error, term()}
  @callback write(path :: String.t(), content :: iodata()) :: :ok | {:error, term()}
  @callback exists?(path :: String.t()) :: boolean()
  @callback mtime(path :: String.t()) :: {:ok, DateTime.t()} | {:error, term()}
end

