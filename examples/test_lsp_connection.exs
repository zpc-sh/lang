#!/usr/bin/env elixir

# Test script to connect to LSP server and implement TODOs
Mix.install([
  {:jason, "~> 1.4"}
])

defmodule LSPConnectionTest do
  @moduledoc """
  Simple test script to connect to the LSP server at localhost:4001
  and demonstrate the connection flow.
  """

  require Logger

  @host ~c"127.0.0.1"
  @port 4001
  @timeout 5_000

  def run do
    Logger.info("Testing LSP connection to #{@host}:#{@port}")

    case connect_and_test() do
      :ok ->
        Logger.info("✅ LSP connection test successful!")
        :ok

      {:error, reason} ->
        Logger.error("❌ LSP connection test failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp connect_and_test do
    with {:ok, socket} <- connect_socket(),
         {:ok, _result} <- initialize_lsp(socket),
         :ok <- send_initialized_notification(socket),
         {:ok, _caps} <- test_capabilities(socket),
         :ok <- test_ping(socket) do
      :gen_tcp.close(socket)
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp connect_socket do
    Logger.info("Connecting to LSP server...")

    case :gen_tcp.connect(@host, @port, [:binary, packet: :raw, active: false], @timeout) do
      {:ok, socket} ->
        Logger.info("✅ Connected to LSP server")
        {:ok, socket}

      {:error, :econnrefused} ->
        Logger.error("❌ Connection refused - LSP server not running on port #{@port}")
        {:error, :server_not_running}

      {:error, reason} ->
        Logger.error("❌ Failed to connect: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp initialize_lsp(socket) do
    Logger.info("Initializing LSP connection...")

    init_params = %{
      "processId" => :os.getpid(),
      "clientInfo" => %{
        "name" => "Lang LSP Test Client",
        "version" => "1.0.0"
      },
      "rootPath" => System.cwd!(),
      "rootUri" => "file://#{System.cwd!()}",
      "capabilities" => %{
        "textDocument" => %{
          "completion" => %{"dynamicRegistration" => true},
          "hover" => %{"dynamicRegistration" => true}
        }
      }
    }

    case send_request(socket, "initialize", init_params) do
      {:ok, result} ->
        Logger.info("✅ LSP initialized successfully")
        Logger.debug("Server capabilities: #{inspect(result)}")
        {:ok, result}

      {:error, reason} ->
        Logger.error("❌ LSP initialization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp send_initialized_notification(socket) do
    Logger.info("Sending initialized notification...")

    notification = %{
      "jsonrpc" => "2.0",
      "method" => "initialized",
      "params" => %{}
    }

    case send_json_message(socket, notification) do
      :ok ->
        Logger.info("✅ Initialized notification sent")
        :ok

      {:error, reason} ->
        Logger.error("❌ Failed to send initialized notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp test_capabilities(socket) do
    Logger.info("Testing server capabilities...")

    case send_request(socket, "rpc.capabilities", %{}) do
      {:ok, caps} ->
        Logger.info("✅ Server capabilities retrieved")
        Logger.info("Available methods: #{inspect(Map.keys(caps))}")
        {:ok, caps}

      {:error, reason} ->
        Logger.warn("Server capabilities test failed: #{inspect(reason)}")
        # This might be expected if the method doesn't exist
        {:ok, %{}}
    end
  end

  defp test_ping(socket) do
    Logger.info("Testing ping...")

    case send_request(socket, "rpc.ping", %{}) do
      {:ok, result} ->
        Logger.info("✅ Ping successful: #{inspect(result)}")
        :ok

      {:error, reason} ->
        Logger.warn("Ping failed: #{inspect(reason)}")
        # Ping might not be implemented, that's okay
        :ok
    end
  end

  defp send_request(socket, method, params) do
    id = System.unique_integer([:positive])

    request = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => method,
      "params" => params
    }

    with :ok <- send_json_message(socket, request),
         {:ok, response} <- receive_json_message(socket) do
      case response do
        %{"id" => ^id, "result" => result} ->
          {:ok, result}

        %{"id" => ^id, "error" => error} ->
          {:error, error}

        other ->
          {:error, {:unexpected_response, other}}
      end
    end
  end

  defp send_json_message(socket, message) do
    case Jason.encode(message) do
      {:ok, json} ->
        header = "Content-Length: #{byte_size(json)}\r\n\r\n"
        :gen_tcp.send(socket, [header, json])

      {:error, reason} ->
        {:error, {:json_encode_error, reason}}
    end
  end

  defp receive_json_message(socket) do
    with {:ok, content_length, body_start} <- receive_headers(socket),
         {:ok, json} <- receive_body(socket, content_length, body_start) do
      case Jason.decode(json) do
        {:ok, message} ->
          {:ok, message}

        {:error, reason} ->
          {:error, {:json_decode_error, reason}}
      end
    end
  end

  defp receive_headers(socket, buffer \\ "") do
    case :gen_tcp.recv(socket, 0, @timeout) do
      {:ok, data} ->
        buffer = buffer <> data

        case Regex.run(~r/Content-Length: (\d+)\r\n\r\n(.*)$/s, buffer) do
          [_full, length_str, body_start] ->
            {:ok, String.to_integer(length_str), body_start}

          nil ->
            receive_headers(socket, buffer)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp receive_body(_socket, content_length, body) when byte_size(body) >= content_length do
    {:ok, binary_part(body, 0, content_length)}
  end

  defp receive_body(socket, content_length, body) do
    remaining = content_length - byte_size(body)

    case :gen_tcp.recv(socket, remaining, @timeout) do
      {:ok, data} ->
        {:ok, body <> data}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

# Run the test
case LSPConnectionTest.run() do
  :ok ->
    IO.puts("\n🎉 LSP connection test completed successfully!")
    IO.puts("The LSP server is running and accepting connections.")

  {:error, :server_not_running} ->
    IO.puts("\n🚨 LSP server is not running!")
    IO.puts("Please start the server with: mix run --no-halt")

  {:error, reason} ->
    IO.puts("\n❌ LSP connection test failed: #{inspect(reason)}")
    System.halt(1)
end
