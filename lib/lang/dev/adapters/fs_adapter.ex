defmodule Lang.Dev.FSAdapter do
  @moduledoc """
  Behaviour for file system operations used in the dev model pipeline.
  """
  @callback scan(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback preview(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  @callback write(String.t(), String.t()) :: :ok | {:error, term()}
end

defmodule Lang.Dev.FSAdapter.Default do
  @moduledoc "Default FS adapter: reads via FSScanner, writes via File.write"
  @behaviour Lang.Dev.FSAdapter

  def scan(dir, opts), do: Lang.Native.FSScanner.scan(dir, opts)
  def preview(path, opts), do: Lang.Native.FSScanner.preview(path, opts)
  def write(path, content), do: File.write(path, content)
end

