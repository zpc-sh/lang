defmodule Mix.Tasks.Lsp.Ping do
  use Mix.Task
  @shortdoc "Ping the local LSP server on localhost:4001"

  @moduledoc """
  Performs a simple `rpc.ping` call against the local LSP server using TCP framing.

      mix lsp.ping

  Respects `LSP_PORT` if set.
  """

  alias Lang.LSP.API

  @impl true
  def run(_args) do
    Mix.Task.run("loadpaths")

    case API.ping() do
      {:ok, result} ->
        Mix.shell().info("LSP ping OK: #{inspect(result)}")

      {:error, reason} ->
        Mix.shell().error("LSP ping FAILED: #{inspect(reason)}")
    end
  end
end
