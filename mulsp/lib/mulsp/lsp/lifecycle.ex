defmodule Mulsp.LSP.Lifecycle do
  @moduledoc """
  LSP lifecycle handlers: initialize, initialized, shutdown, exit.

  Returns capabilities tailored to this mulsp instance's partition config.
  The capabilities tell the client exactly what this servelet handles
  locally vs. what gets proxied.
  """

  @behaviour Mulsp.LSP.Handler

  @impl true
  def handle(%{method: "initialize"} = _request) do
    partition =
      case GenServer.whereis(Mulsp.Dispatch) do
        nil -> Mulsp.Partition.load()
        _pid -> Mulsp.Dispatch |> :sys.get_state() |> Map.get(:partition)
      end

    capabilities = build_capabilities(partition)

    result = %{
      capabilities: capabilities,
      serverInfo: %{
        name: "mulsp",
        version: "0.1.0",
        nodeId: partition.node_id
      }
    }

    {:ok, result}
  end

  def handle(%{method: "initialized"}) do
    # Post-init handshake. Good time to start mesh discovery.
    Mulsp.Mesh.Cluster.discover()
    {:ok, nil}
  end

  def handle(%{method: "shutdown"}) do
    # Graceful shutdown — close DC connections, notify peers
    Mulsp.Mesh.Cluster.announce_shutdown()
    {:ok, nil}
  end

  def handle(%{method: "exit"}) do
    # Hard exit
    spawn(fn ->
      Process.sleep(100)
      System.stop(0)
    end)

    {:ok, nil}
  end

  def handle(_request) do
    {:error, :method_not_found, "not a lifecycle method"}
  end

  defp build_capabilities(partition) do
    text_sync =
      if "textDocument/didOpen" in partition.local_methods do
        %{openClose: true, change: 1}
      end

    %{
      textDocumentSync: text_sync,
      # Only advertise completion if we handle it locally
      completionProvider:
        if("textDocument/completion" in partition.local_methods,
          do: %{triggerCharacters: [".", ":", "/"]},
          else: nil
        ),
      hoverProvider: "textDocument/hover" in partition.local_methods,
      # mulsp-specific capabilities
      experimental: %{
        mulsp: %{
          nodeId: partition.node_id,
          protocols: partition.protocols,
          dcEnabled: partition.dc_enabled,
          guardLevel: partition.guard_level,
          gopherPort: partition.gopher_port,
          fingerPort: partition.finger_port
        }
      }
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
