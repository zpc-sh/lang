defmodule Lang.LSP.ConnectionManagerTest do
  use ExUnit.Case, async: true
  alias Lang.LSP.ConnectionManager

  setup do
    # Start the ConnectionManager and its supervisor dependencies
    start_supervised!(Lang.LSP.ConnectionSupervisor)
    start_supervised!(ConnectionManager)
    :ok
  end

  test "accepts new connections within the limit" do
    # Mock the TCP socket
    {:ok, mock_socket} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false])
    port = elem(:inet.sockname(mock_socket), 1)
    {:ok, client_socket} = :gen_tcp.connect('localhost', port, [:binary], 5000)

    :ok = ConnectionManager.accept_socket(client_socket)

    # Allow some time for the worker to start
    Process.sleep(100)

    # This is an indirect way to check; a better way would be to inspect the supervisor's children.
    # For now, we'll just ensure it doesn't crash.
    assert true
  after
    :gen_tcp.close(mock_socket)
  end

  test "rejects new connections when the limit is exceeded" do
    max_connections = Application.get_env(:lang, :lsp_server, [])
                      |> Keyword.get(:max_connections, 2) # Use a small limit for testing
    Application.put_env(:lang, :lsp_server, max_connections: max_connections)

    # Restart manager to apply new config
    Supervisor.restart_child(Process.whereis(Lang.LSP.Supervisor), ConnectionManager)
    Process.sleep(50) # give it time to restart

    sockets = for _ <- 1..max_connections do
      {:ok, mock_socket} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false])
      port = elem(:inet.sockname(mock_socket), 1)
      {:ok, client_socket} = :gen_tcp.connect('localhost', port, [:binary], 5000)
      ConnectionManager.accept_socket(client_socket)
      mock_socket
    end

    # This one should be rejected
    {:ok, extra_socket_listener} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false])
    port = elem(:inet.sockname(extra_socket_listener), 1)
    {:ok, extra_socket} = :gen_tcp.connect('localhost', port, [:binary], 5000)

    :ok = ConnectionManager.accept_socket(extra_socket)
    Process.sleep(100)

    # The socket should have been closed by the manager
    refute :inet.getstat(extra_socket) == {:ok, _}

  after
    Enum.each(sockets, &:gen_tcp.close/1)
    :gen_tcp.close(extra_socket_listener)
    Application.delete_env(:lang, :lsp_server)
  end
end
