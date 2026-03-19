defmodule Lang.Storage.Adapter do
  @moduledoc """
  Behaviour for storage backends used by Lang.Storage.

  Implementations must enforce path normalization under a workspace root
  and use native NIFs (Lang.Native.FSScanner) for filesystem operations.
  """

  @type path :: String.t()
  @type uri :: String.t()
  @type entry :: %{required(:name) => String.t(), required(:uri) => uri, required(:kind) => :file | :directory, optional(:size) => non_neg_integer(), optional(:mtime) => term()}
  @type stat :: %{required(:exists) => boolean(), optional(:kind) => :file | :directory, optional(:size) => non_neg_integer(), optional(:mtime) => term()}

  @callback list(root :: path, path :: path, opts :: keyword()) :: {:ok, [entry()]} | {:error, term()}
  @callback stat(root :: path, path :: path) :: {:ok, stat()} | {:error, term()}
  @callback read(root :: path, path :: path, opts :: keyword()) :: {:ok, binary()} | {:error, term()}
  @callback preview(root :: path, path :: path, max_lines :: pos_integer()) :: {:ok, [String.t()]} | {:error, term()}
  @callback search(root :: path, pattern :: String.t(), opts :: keyword()) :: {:ok, list(map())} | {:error, term()}
  @callback search_code(root :: path, language :: String.t(), query :: String.t(), opts :: keyword()) :: {:ok, list(map())} | {:error, term()}
  @callback scan(root :: path, opts :: keyword()) :: {:ok, map()} | {:error, term()}
  @callback write(root :: path, path :: path, content :: iodata(), mode :: :replace | :append) :: :ok | {:error, term()}
  @callback move(root :: path, from :: path, to :: path) :: :ok | {:error, term()}
  @callback delete(root :: path, path :: path, recursive? :: boolean()) :: :ok | {:error, term()}
  @callback normalize(root :: path, path :: path) :: {:ok, path()} | {:error, term()}
end

