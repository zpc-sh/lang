#!/usr/bin/env elixir

# Interactive LSP Chat Client for LANG Universal Text Intelligence Platform
# Usage: elixir lsp_chat.exs

Mix.install([
  {:jason, "~> 1.4"}
])

defmodule LSPChatClient do
  @moduledoc """
  Interactive chat client for the LANG LSP system.

  Connects to the LSP server at localhost:4001 and provides a conversational
  interface with AI agents for code assistance, debugging, and learning.
  """

  require Logger

  @host ~c"127.0.0.1"
  @port 4001
  @timeout 30_000

  def start do
    IO.puts("🚀 LANG LSP Chat Client Starting...")
    IO.puts("Connecting to LSP server at #{@host}:#{@port}")

    case connect_to_lsp() do
      {:ok, connection} ->
        start_chat_session(connection)

      {:error, reason} ->
        IO.puts("❌ Failed to connect: #{inspect(reason)}")
        IO.puts("\nMake sure the LANG LSP server is running:")
        IO.puts("  cd lang && mix run --no-halt")
        System.halt(1)
    end
  end

  defp connect_to_lsp do
    case :gen_tcp.connect(@host, @port, [:binary, packet: :raw, active: false], @timeout) do
      {:ok, socket} ->
        case initialize_lsp_connection(socket) do
          {:ok, _} ->
            IO.puts("✅ Connected to LANG LSP server")
            {:ok, %{socket: socket, initialized: true}}

          {:error, reason} ->
            :gen_tcp.close(socket)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp initialize_lsp_connection(socket) do
    init_request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "processId" => :os.getpid(),
        "clientInfo" => %{
          "name" => "LANG Chat Client",
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
    }

    with :ok <- send_lsp_message(socket, init_request),
         {:ok, _response} <- receive_lsp_message(socket),
         :ok <- send_initialized_notification(socket) do
      {:ok, :initialized}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_initialized_notification(socket) do
    notification = %{
      "jsonrpc" => "2.0",
      "method" => "initialized",
      "params" => %{}
    }

    send_lsp_message(socket, notification)
  end

  defp start_chat_session(connection) do
    IO.puts("\n🤖 LANG AI Assistant Ready!")
    IO.puts("Choose your AI agent personality:")
    IO.puts("  1. 🛡️  Security Analyst - Focus on security and vulnerabilities")
    IO.puts("  2. ⚡ Performance Expert - Optimize for speed and efficiency")
    IO.puts("  3. 🔧 Refactor Specialist - Clean code and best practices")
    IO.puts("  4. 🚀 Startup Advisor - Fast MVP development")
    IO.puts("  5. 👨‍🏫 Code Mentor - Learning and education focused")
    IO.puts("  6. 💡 General Assistant - Balanced help with everything")

    agent_choice = IO.gets("Enter your choice (1-6): ") |> String.trim()
    agent_type = map_agent_choice(agent_choice)

    IO.puts("\nStarting chat session with #{agent_type}...")

    case start_lsp_chat_session(connection, agent_type) do
      {:ok, session_info} ->
        IO.puts("✅ #{session_info["greeting"]}")
        IO.puts("\nCapabilities:")

        Enum.each(session_info["capabilities"], fn cap ->
          IO.puts("  • #{cap}")
        end)

        IO.puts("\n" <> String.duplicate("=", 60))
        IO.puts("Chat started! Type your questions or 'quit' to exit.")
        IO.puts("Commands: /agent <name> - switch agent, /help - show help")
        IO.puts(String.duplicate("=", 60) <> "\n")

        chat_loop(connection, session_info["session_id"], agent_type)

      {:error, reason} ->
        IO.puts("❌ Failed to start chat session: #{reason}")
    end
  end

  defp map_agent_choice(choice) do
    case choice do
      "1" -> "security_analyst"
      "2" -> "performance_expert"
      "3" -> "refactor_specialist"
      "4" -> "startup_advisor"
      "5" -> "code_mentor"
      "6" -> "general"
      _ -> "general"
    end
  end

  defp start_lsp_chat_session(connection, agent_type) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "lang.conversation.chat",
      "params" => %{
        "action" => "start",
        "agent" => agent_type,
        "workspace_path" => System.cwd!()
      }
    }

    case send_lsp_request(connection, request) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp chat_loop(connection, session_id, current_agent) do
    message = IO.gets("#{current_agent}> ") |> String.trim()

    case message do
      "quit" ->
        end_chat_session(connection, session_id)
        IO.puts("👋 Chat session ended. Goodbye!")

      "/help" ->
        show_help()
        chat_loop(connection, session_id, current_agent)

      "/agent " <> new_agent ->
        case switch_agent(connection, session_id, String.trim(new_agent)) do
          {:ok, response} ->
            IO.puts("🔄 #{response["transition_message"]}")
            chat_loop(connection, session_id, response["new_agent"])

          {:error, reason} ->
            IO.puts("❌ Failed to switch agent: #{reason}")
            chat_loop(connection, session_id, current_agent)
        end

      "" ->
        chat_loop(connection, session_id, current_agent)

      user_message ->
        case send_chat_message(connection, session_id, user_message, current_agent) do
          {:ok, response} ->
            IO.puts("\n🤖 #{response["response"]}")

            if Map.has_key?(response, "follow_up_suggestions") do
              IO.puts("\n💡 Suggestions:")

              Enum.each(response["follow_up_suggestions"], fn suggestion ->
                IO.puts("  • #{suggestion}")
              end)
            end

            IO.puts("")
            chat_loop(connection, session_id, current_agent)

          {:error, reason} ->
            IO.puts("❌ Error: #{reason}")
            chat_loop(connection, session_id, current_agent)
        end
    end
  end

  defp send_chat_message(connection, session_id, message, agent) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "lang.conversation.chat",
      "params" => %{
        "action" => "chat",
        "session_id" => session_id,
        "message" => message,
        "agent" => agent,
        "workspace" => %{
          "path" => System.cwd!()
        }
      }
    }

    send_lsp_request(connection, request)
  end

  defp switch_agent(connection, session_id, new_agent) do
    # Map user-friendly names to agent types
    agent_type =
      case String.downcase(new_agent) do
        "security" -> "security_analyst"
        "performance" -> "performance_expert"
        "refactor" -> "refactor_specialist"
        "startup" -> "startup_advisor"
        "mentor" -> "code_mentor"
        "general" -> "general"
        other -> other
      end

    request = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "lang.conversation.chat",
      "params" => %{
        "action" => "switch_agent",
        "session_id" => session_id,
        "agent" => agent_type
      }
    }

    send_lsp_request(connection, request)
  end

  defp end_chat_session(connection, session_id) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "lang.lsp.chat",
      "params" => %{
        "action" => "end_session",
        "session_id" => session_id
      }
    }

    send_lsp_request(connection, request)
  end

  defp show_help do
    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("LANG LSP Chat Help")
    IO.puts(String.duplicate("=", 50))
    IO.puts("Commands:")
    IO.puts("  quit                 - Exit the chat")
    IO.puts("  /help               - Show this help")
    IO.puts("  /agent <name>       - Switch AI agent personality")
    IO.puts("")
    IO.puts("Available agents:")
    IO.puts("  security    - Security and vulnerability focus")
    IO.puts("  performance - Speed and optimization focus")
    IO.puts("  refactor    - Clean code and best practices")
    IO.puts("  startup     - Fast MVP development")
    IO.puts("  mentor      - Learning and education")
    IO.puts("  general     - Balanced assistance")
    IO.puts("")
    IO.puts("Tips:")
    IO.puts("  • Paste code blocks for analysis")
    IO.puts("  • Ask questions about your codebase")
    IO.puts("  • Request explanations and tutorials")
    IO.puts("  • Get debugging help and suggestions")
    IO.puts(String.duplicate("=", 50) <> "\n")
  end

  defp send_lsp_request(connection, request) do
    case send_lsp_message(connection.socket, request) do
      :ok ->
        case receive_lsp_message(connection.socket) do
          {:ok, response} ->
            case response do
              %{"error" => error} -> {:error, error["message"]}
              %{"result" => result} -> {:ok, result}
              other -> {:ok, other}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_lsp_message(socket, message) do
    case Jason.encode(message) do
      {:ok, json} ->
        header = "Content-Length: #{byte_size(json)}\r\n\r\n"
        :gen_tcp.send(socket, [header, json])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp receive_lsp_message(socket) do
    case receive_headers(socket) do
      {:ok, content_length, body_start} ->
        case receive_body(socket, content_length, body_start) do
          {:ok, json} ->
            case Jason.decode(json) do
              {:ok, message} -> {:ok, message}
              {:error, reason} -> {:error, {:json_decode, reason}}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
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
      {:ok, data} -> {:ok, body <> data}
      {:error, reason} -> {:error, reason}
    end
  end
end

# ASCII Art Banner
IO.puts("""
██╗      █████╗ ███╗   ██╗ ██████╗     ██╗     ███████╗██████╗
██║     ██╔══██╗████╗  ██║██╔════╝     ██║     ██╔════╝██╔══██╗
██║     ███████║██╔██╗ ██║██║  ███╗    ██║     ███████╗██████╔╝
██║     ██╔══██║██║╚██╗██║██║   ██║    ██║     ╚════██║██╔═══╝
███████╗██║  ██║██║ ╚████║╚██████╔╝    ███████╗███████║██║
╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝     ╚══════╝╚══════╝╚═╝

    Universal Text Intelligence Platform - Chat Interface
""")

# Start the chat client
LSPChatClient.start()
