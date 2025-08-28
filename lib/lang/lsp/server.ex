defmodule Lang.LSP.Server do
  @moduledoc """
  The main LSP server implementation that handles TCP/stdio connections and JSON-RPC protocol.

  This server supports both TCP socket connections and stdio mode for VSCode integration.
  It handles the full LSP lifecycle and routes messages to appropriate handlers.
  """

  use GenServer
  require Logger

  alias Lang.LSP.{Dispatch, Registry, StreamingProtocol, PhoenixIntegration}
  alias Lang.TextIntelligence.AnalysisEngine

  @default_port 4001
  @read_timeout 60_000

  defstruct [
    :mode,
    :port,
    :listen_socket,
    :clients,
    :documents,
    :initialized,
    :root_uri,
    :capabilities,
    :shutdown_requested
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def stop(reason \\ :normal) do
    GenServer.stop(__MODULE__, reason)
  end

  def get_info do
    GenServer.call(__MODULE__, :get_info)
  end

  def get_document(uri) do
    GenServer.call(__MODULE__, {:get_document, uri})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    mode = Keyword.get(opts, :mode, :tcp)
    port = Keyword.get(opts, :port, @default_port)

    state = %__MODULE__{
      mode: mode,
      port: port,
      clients: %{},
      documents: %{},
      initialized: false,
      shutdown_requested: false
    }

    case mode do
      :tcp ->
        {:ok, state, {:continue, :start_tcp_server}}

      :stdio ->
        {:ok, state, {:continue, :start_stdio_server}}

      _ ->
        {:stop, {:invalid_mode, mode}}
    end
  end

  @impl true
  def handle_continue(:start_tcp_server, state) do
    case :gen_tcp.listen(state.port, [
           :binary,
           packet: :raw,
           active: false,
           reuseaddr: true,
           keepalive: true
         ]) do
      {:ok, listen_socket} ->
        Logger.info("LSP Server listening on port #{state.port}")
        # Start accepting connections
        spawn_link(fn -> accept_loop(listen_socket) end)
        {:noreply, %{state | listen_socket: listen_socket}}

      {:error, reason} ->
        Logger.error("Failed to start LSP server: #{inspect(reason)}")
        {:stop, {:listen_failed, reason}, state}
    end
  end

  @impl true
  def handle_continue(:start_stdio_server, state) do
    Logger.info("LSP Server starting in stdio mode")
    # Start reading from stdin
    spawn_link(fn -> stdio_loop() end)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      mode: state.mode,
      port: state.port,
      initialized: state.initialized,
      root_uri: state.root_uri,
      active_documents: map_size(state.documents),
      connected_clients: map_size(state.clients),
      version: "1.0.0"
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call({:get_document, uri}, _from, state) do
    {:reply, Map.get(state.documents, uri), state}
  end

  @impl true
  def handle_info({:lsp_request, client_id, request}, state) do
    state = handle_lsp_request(client_id, request, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:client_connected, client_id, socket}, state) do
    Logger.info("LSP client connected: #{client_id}")

    PhoenixIntegration.report_metrics(
      :connection,
      %{client_count: map_size(state.clients) + 1},
      %{action: :connect}
    )

    clients =
      Map.put(state.clients, client_id, %{
        socket: socket,
        buffer: "",
        initialized: false
      })

    {:noreply, %{state | clients: clients}}
  end

  @impl true
  def handle_info({:client_disconnected, client_id}, state) do
    Logger.info("LSP client disconnected: #{client_id}")

    PhoenixIntegration.report_metrics(
      :connection,
      %{client_count: map_size(state.clients) - 1},
      %{action: :disconnect}
    )

    clients = Map.delete(state.clients, client_id)
    {:noreply, %{state | clients: clients}}
  end

  @impl true
  def handle_cast({:broadcast_notification, notification}, state) do
    # Send notification to all connected clients
    Enum.each(state.clients, fn {_id, %{socket: socket}} ->
      send_json_rpc(socket, notification)
    end)

    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("LSP Server terminating: #{inspect(reason)}")

    # Close all client connections
    Enum.each(state.clients, fn {_id, %{socket: socket}} ->
      :gen_tcp.close(socket)
    end)

    # Close listen socket
    if state.listen_socket do
      :gen_tcp.close(state.listen_socket)
    end

    :ok
  end

  # Private functions

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        client_id = generate_client_id()

        # Configure socket
        :inet.setopts(client_socket,
          active: true,
          nodelay: true,
          keepalive: true
        )

        # Notify server of new connection
        send(self(), {:client_connected, client_id, client_socket})

        # Start client handler
        spawn_link(fn -> client_loop(client_id, client_socket, "") end)

        # Continue accepting
        accept_loop(listen_socket)

      {:error, :closed} ->
        Logger.info("LSP server socket closed")
        :ok

      {:error, reason} ->
        Logger.error("Accept error: #{inspect(reason)}")
        Process.sleep(1000)
        accept_loop(listen_socket)
    end
  end

  defp client_loop(client_id, socket, buffer) do
    receive do
      {:tcp, ^socket, data} ->
        buffer = buffer <> data
        {messages, remaining_buffer} = extract_messages(buffer)

        Enum.each(messages, fn msg ->
          send(Lang.LSP.Server, {:lsp_request, client_id, msg})
        end)

        client_loop(client_id, socket, remaining_buffer)

      {:tcp_closed, ^socket} ->
        send(Lang.LSP.Server, {:client_disconnected, client_id})
        :ok

      {:tcp_error, ^socket, reason} ->
        Logger.error("TCP error for client #{client_id}: #{inspect(reason)}")
        send(Lang.LSP.Server, {:client_disconnected, client_id})
        :ok

      {:send_response, response} ->
        send_json_rpc(socket, response)
        client_loop(client_id, socket, buffer)
    end
  end

  defp stdio_loop do
    case IO.gets("") do
      :eof ->
        Logger.info("LSP stdio closed")
        :ok

      {:error, reason} ->
        Logger.error("Stdio error: #{inspect(reason)}")
        :ok

      data ->
        # For stdio mode, we need to handle Content-Length headers
        case parse_stdio_message(data) do
          {:ok, message} ->
            send(Lang.LSP.Server, {:lsp_request, :stdio, message})

          {:error, reason} ->
            Logger.error("Failed to parse stdio message: #{inspect(reason)}")
        end

        stdio_loop()
    end
  end

  defp extract_messages(buffer) do
    # Extract JSON-RPC messages from buffer
    # Look for Content-Length header pattern
    case Regex.run(~r/Content-Length: (\d+)\r\n\r\n/U, buffer) do
      [full_match, length_str] ->
        header_length = byte_size(full_match)
        content_length = String.to_integer(length_str)
        total_length = header_length + content_length

        if byte_size(buffer) >= total_length do
          # We have a complete message
          <<_header::binary-size(header_length), json::binary-size(content_length), rest::binary>> =
            buffer

          case Jason.decode(json) do
            {:ok, message} ->
              {messages, remaining} = extract_messages(rest)
              {[message | messages], remaining}

            {:error, _reason} ->
              # Skip this message and continue
              extract_messages(rest)
          end
        else
          # Incomplete message, wait for more data
          {[], buffer}
        end

      nil ->
        # No complete header found
        {[], buffer}
    end
  end

  defp parse_stdio_message(data) do
    # Parse Content-Length header and JSON body
    lines = String.split(data, "\n")

    case parse_headers(lines, %{}) do
      {:ok, headers, body_lines} ->
        body = Enum.join(body_lines, "\n")
        Jason.decode(body)

      error ->
        error
    end
  end

  defp parse_headers([line | rest], headers) do
    case String.trim(line) do
      "" ->
        # Empty line signals end of headers
        {:ok, headers, rest}

      header_line ->
        case String.split(header_line, ":", parts: 2) do
          [key, value] ->
            headers = Map.put(headers, String.trim(key), String.trim(value))
            parse_headers(rest, headers)

          _ ->
            {:error, :invalid_header}
        end
    end
  end

  defp parse_headers([], _headers) do
    {:error, :incomplete_headers}
  end

  defp handle_lsp_request(client_id, message, state) do
    start_time = System.monotonic_time(:millisecond)

    # Route based on method
    response =
      case message do
        %{"method" => "initialize", "id" => id, "params" => params} ->
          handle_initialize(id, params, state)

        %{"method" => "initialized"} ->
          state = %{state | initialized: true}
          Logger.info("LSP server initialized")
          nil

        %{"method" => "shutdown", "id" => id} ->
          state = %{state | shutdown_requested: true}
          %{"jsonrpc" => "2.0", "id" => id, "result" => nil}

        %{"method" => "exit"} ->
          if state.shutdown_requested do
            System.stop(0)
          else
            System.stop(1)
          end

          nil

        %{"method" => "textDocument/didOpen", "params" => params} ->
          handle_did_open(params, state)

        %{"method" => "textDocument/didChange", "params" => params} ->
          handle_did_change(params, state)

        %{"method" => "textDocument/didSave", "params" => params} ->
          handle_did_save(params, state)

        %{"method" => "textDocument/didClose", "params" => params} ->
          handle_did_close(params, state)

        %{"method" => "textDocument/completion", "id" => id, "params" => params} ->
          handle_completion(id, params, state)

        %{"method" => "textDocument/hover", "id" => id, "params" => params} ->
          handle_hover(id, params, state)

        %{"method" => "textDocument/definition", "id" => id, "params" => params} ->
          handle_definition(id, params, state)

        %{"method" => "textDocument/references", "id" => id, "params" => params} ->
          handle_references(id, params, state)

        %{"method" => "textDocument/documentSymbol", "id" => id, "params" => params} ->
          handle_document_symbol(id, params, state)

        %{"method" => "textDocument/formatting", "id" => id, "params" => params} ->
          handle_formatting(id, params, state)

        %{"method" => "workspace/symbol", "id" => id, "params" => params} ->
          handle_workspace_symbol(id, params, state)

        %{"method" => "workspace/executeCommand", "id" => id, "params" => params} ->
          handle_execute_command(id, params, state)

        # Custom Lang methods
        %{"method" => method} when is_binary(method) ->
          if String.starts_with?(method, "lang.") do
            Dispatch.process(message)
          else
            handle_unknown_method(message)
          end

        _ ->
          Logger.warn("Invalid LSP message: #{inspect(message)}")
          nil
      end

    # Send response if we have one
    if response do
      duration = System.monotonic_time(:millisecond) - start_time

      PhoenixIntegration.report_metrics(:request, %{duration: duration}, %{
        method: message["method"]
      })

      case state.mode do
        :tcp ->
          client = Map.get(state.clients, client_id)
          if client, do: send_json_rpc(client.socket, response)

        :stdio ->
          send_json_rpc(:stdio, response)
      end
    end

    state
  end

  defp handle_initialize(id, params, state) do
    # Extract initialization parameters
    root_uri = params["rootUri"] || params["rootPath"]
    client_info = params["clientInfo"] || %{}

    Logger.info("LSP initialize request from #{client_info["name"] || "unknown"} for #{root_uri}")

    # Build server capabilities
    capabilities = %{
      "textDocumentSync" => %{
        "openClose" => true,
        # Incremental
        "change" => 2,
        "save" => %{"includeText" => true}
      },
      "completionProvider" => %{
        "triggerCharacters" => [".", ":", "@", "&", "%", "!", "?", "/", "<", ">", " "],
        "resolveProvider" => true
      },
      "hoverProvider" => true,
      "definitionProvider" => true,
      "referencesProvider" => true,
      "documentSymbolProvider" => true,
      "workspaceSymbolProvider" => true,
      "documentFormattingProvider" => true,
      "executeCommandProvider" => %{
        "commands" => [
          "lang.analyzeFile",
          "lang.generateCompletion",
          "lang.explainCode",
          "lang.refactorCode",
          "lang.generateTests"
        ]
      },
      "workspace" => %{
        "workspaceFolders" => %{
          "supported" => true,
          "changeNotifications" => true
        }
      }
    }

    state = %{state | root_uri: root_uri, capabilities: capabilities}

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "capabilities" => capabilities,
        "serverInfo" => %{
          "name" => "Lang LSP",
          "version" => "1.0.0"
        }
      }
    }
  end

  defp handle_did_open(
         %{"textDocument" => %{"uri" => uri, "text" => text, "languageId" => language_id}},
         state
       ) do
    Logger.debug("Document opened: #{uri}")

    # Store document
    document = %{
      uri: uri,
      text: text,
      language_id: language_id,
      version: 0
    }

    state = put_in(state.documents[uri], document)

    # Analyze document asynchronously
    Task.start(fn ->
      analyze_and_publish_diagnostics(uri, text)
    end)

    state
  end

  defp handle_did_change(
         %{"textDocument" => %{"uri" => uri, "version" => version}, "contentChanges" => changes},
         state
       ) do
    Logger.debug("Document changed: #{uri}")

    # Update document
    case Map.get(state.documents, uri) do
      nil ->
        Logger.warn("Changed document not found: #{uri}")
        state

      document ->
        # Apply changes (we support incremental sync)
        new_text = apply_content_changes(document.text, changes)

        document = %{document | text: new_text, version: version}

        state = put_in(state.documents[uri], document)

        # Debounced analysis
        Task.start(fn ->
          Process.sleep(500)
          analyze_and_publish_diagnostics(uri, new_text)
        end)

        state
    end
  end

  defp handle_did_save(%{"textDocument" => %{"uri" => uri}}, state) do
    Logger.debug("Document saved: #{uri}")

    # Trigger full analysis on save
    case Map.get(state.documents, uri) do
      nil ->
        state

      document ->
        Task.start(fn ->
          analyze_and_publish_diagnostics(uri, document.text)
        end)

        state
    end
  end

  defp handle_did_close(%{"textDocument" => %{"uri" => uri}}, state) do
    Logger.debug("Document closed: #{uri}")

    # Clear diagnostics
    publish_diagnostics(uri, [])

    # Remove document
    {_, state} = pop_in(state.documents[uri])
    state
  end

  defp handle_completion(id, %{"textDocument" => %{"uri" => uri}, "position" => position}, state) do
    case Map.get(state.documents, uri) do
      nil ->
        error_response(id, :document_not_found)

      document ->
        # Get context at position
        context = get_completion_context(document.text, position)

        # Route to completion handler
        completions =
          case Lang.LSP.Handlers.Completion.handle(
                 uri,
                 document.text,
                 position,
                 %{trigger_kind: 1},
                 %{language: document.language_id}
               ) do
            {:ok, items} -> items
            {:error, _reason} -> []
          end

        # Broadcast for caching
        PhoenixIntegration.broadcast_completions(uri, position, completions)

        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => completions
        }
    end
  end

  defp handle_hover(id, %{"textDocument" => %{"uri" => uri}, "position" => position}, state) do
    case Map.get(state.documents, uri) do
      nil ->
        error_response(id, :document_not_found)

      document ->
        # Get word at position
        word = get_word_at_position(document.text, position)

        # Get hover info from AI
        hover_info =
        case Lang.Providers.Router.route_lsp(:hover, %{
                 word: word,
                 context: get_line_at_position(document.text, position),
                 language: document.language_id
               }) do
            {:ok, info} ->
              %{
                "contents" => %{
                  "kind" => "markdown",
                  "value" => info
                }
              }

            {:error, _reason} ->
              nil
          end

        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => hover_info
        }
    end
  end

  defp handle_definition(id, %{"textDocument" => %{"uri" => uri}, "position" => position}, state) do
    case Map.get(state.documents, uri) do
      nil ->
        error_response(id, :document_not_found)

      document ->
        # Use AI to find definition
        word = get_word_at_position(document.text, position)

        locations =
          case Lang.TextIntelligence.SymbolAnalyzer.find_definition(word, uri, state.root_uri) do
            {:ok, definitions} ->
              Enum.map(definitions, &format_location/1)

            {:error, _reason} ->
              []
          end

        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => locations
        }
    end
  end

  defp handle_references(id, %{"textDocument" => %{"uri" => uri}, "position" => position}, state) do
    case Map.get(state.documents, uri) do
      nil ->
        error_response(id, :document_not_found)

      document ->
        word = get_word_at_position(document.text, position)

        # Find all references
        references =
          case Lang.TextIntelligence.SymbolAnalyzer.find_references(word, state.root_uri) do
            {:ok, refs} ->
              Enum.map(refs, &format_location/1)

            {:error, _reason} ->
              []
          end

        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => references
        }
    end
  end

  defp handle_document_symbol(id, %{"textDocument" => %{"uri" => uri}}, state) do
    case Map.get(state.documents, uri) do
      nil ->
        error_response(id, :document_not_found)

      document ->
        # Extract symbols from document
        symbols =
          case Lang.TextIntelligence.SymbolAnalyzer.extract_symbols(
                 document.text,
                 document.language_id
               ) do
            {:ok, syms} ->
              Enum.map(syms, &format_document_symbol/1)

            {:error, _reason} ->
              []
          end

        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => symbols
        }
    end
  end

  defp handle_formatting(id, %{"textDocument" => %{"uri" => uri}}, state) do
    case Map.get(state.documents, uri) do
      nil ->
        error_response(id, :document_not_found)

      document ->
        # Format document
        edits =
          case Lang.TextIntelligence.Formatter.format(document.text, document.language_id) do
            {:ok, formatted_text} ->
              if formatted_text != document.text do
                [
                  %{
                    "range" => %{
                      "start" => %{"line" => 0, "character" => 0},
                      "end" => get_document_end(document.text)
                    },
                    "newText" => formatted_text
                  }
                ]
              else
                []
              end

            {:error, _reason} ->
              []
          end

        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => edits
        }
    end
  end

  defp handle_workspace_symbol(id, %{"query" => query}, state) do
    # Search across workspace
    case Lang.TextIntelligence.SymbolAnalyzer.search_workspace(query, state.root_uri) do
      {:ok, symbols} when length(symbols) > 100 ->
        # Stream large results
        {:ok, stream_id} = StreamingProtocol.stream_workspace_symbols(query)

        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => %{
            "stream_id" => stream_id,
            "partial" => true
          }
        }

      {:ok, symbols} ->
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => Enum.map(symbols, &format_workspace_symbol/1)
        }

      {:error, _reason} ->
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => []
        }
    end
  end

  defp handle_execute_command(id, %{"command" => command, "arguments" => args}, state) do
    result =
      case command do
        "lang.analyzeFile" ->
          [uri | _] = args
          analyze_file_command(uri, state)

        "lang.generateCompletion" ->
          [uri, position | _] = args
          generate_completion_command(uri, position, state)

        "lang.explainCode" ->
          [uri, range | _] = args
          explain_code_command(uri, range, state)

        "lang.refactorCode" ->
          [uri, range, refactor_type | _] = args
          refactor_code_command(uri, range, refactor_type, state)

        "lang.generateTests" ->
          [uri, range | _] = args
          generate_tests_command(uri, range, state)

        _ ->
          {:error, "Unknown command: #{command}"}
      end

    case result do
      {:ok, response} ->
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => response
        }

      {:error, message} ->
        error_response(id, message)
    end
  end

  defp handle_unknown_method(%{"id" => id, "method" => method}) do
    Logger.warn("Unknown LSP method: #{method}")
    error_response(id, "Method not found: #{method}", -32601)
  end

  defp handle_unknown_method(_) do
    nil
  end

  # Helper functions

  defp send_json_rpc(:stdio, message) do
    json = Jason.encode!(message)
    content_length = byte_size(json)

    IO.write("Content-Length: #{content_length}\r\n\r\n#{json}")
    # Flush
    IO.binwrite(:stdio, <<>>)
  end

  defp send_json_rpc(socket, message) do
    json = Jason.encode!(message)
    content_length = byte_size(json)

    header = "Content-Length: #{content_length}\r\n\r\n"
    :gen_tcp.send(socket, header <> json)
  end

  defp error_response(id, message, code \\ -32603) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => code,
        "message" => to_string(message)
      }
    }
  end

  defp generate_client_id do
    "client_#{:erlang.unique_integer([:positive])}"
  end

  defp analyze_and_publish_diagnostics(uri, text) do
    format = extract_format_from_uri(uri)

    diagnostics =
      case AnalysisEngine.analyze_content(text, format) do
        {:ok, analysis} ->
          format_diagnostics(analysis.diagnostics)

        {:error, _reason} ->
          []
      end

    publish_diagnostics(uri, diagnostics)
  end

  defp publish_diagnostics(uri, diagnostics) do
    # Send to all connected clients
    notification = %{
      "jsonrpc" => "2.0",
      "method" => "textDocument/publishDiagnostics",
      "params" => %{
        "uri" => uri,
        "diagnostics" => diagnostics
      }
    }

    # Broadcast to Phoenix
    PhoenixIntegration.broadcast_diagnostics(uri, diagnostics)

    # Send to all LSP clients
    GenServer.cast(__MODULE__, {:broadcast_notification, notification})
  end

  defp apply_content_changes(text, changes) do
    Enum.reduce(changes, text, fn change, acc ->
      case change do
        %{"range" => range, "text" => new_text} ->
          apply_range_change(acc, range, new_text)

        %{"text" => new_text} ->
          # Full document change
          new_text
      end
    end)
  end

  defp apply_range_change(text, range, new_text) do
    lines = String.split(text, "\n", parts: :infinity)

    start_line = range["start"]["line"]
    start_char = range["start"]["character"]
    end_line = range["end"]["line"]
    end_char = range["end"]["character"]

    # Apply the change (simplified - real implementation would be more complex)
    # This is a placeholder that would need proper line/character handling
    new_text
  end

  defp get_completion_context(text, %{"line" => line, "character" => character}) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")

    prefix = String.slice(current_line, 0, character)
    suffix = String.slice(current_line, character..-1)

    %{
      prefix: prefix,
      suffix: suffix,
      line: current_line,
      line_number: line,
      character: character
    }
  end

  defp get_word_at_position(text, %{"line" => line, "character" => character}) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")

    # Find word boundaries
    before = String.slice(current_line, 0, character) |> String.reverse()
    after_cursor = String.slice(current_line, character..-1)

    word_before = Regex.run(~r/^[\w_]+/, before) |> List.first("") |> String.reverse()
    word_after = Regex.run(~r/^[\w_]+/, after_cursor) |> List.first("")

    word_before <> word_after
  end

  defp get_line_at_position(text, %{"line" => line}) do
    String.split(text, "\n") |> Enum.at(line, "")
  end

  defp get_document_end(text) do
    lines = String.split(text, "\n")
    last_line = length(lines) - 1
    last_line_text = List.last(lines) || ""

    %{
      "line" => last_line,
      "character" => String.length(last_line_text)
    }
  end

  defp extract_format_from_uri(uri) do
    case Path.extname(uri) do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      ".py" -> "python"
      ".rs" -> "rust"
      ".go" -> "go"
      ".rb" -> "ruby"
      ".md" -> "markdown"
      ".json" -> "json"
      ".yaml" -> "yaml"
      ".yml" -> "yaml"
      _ -> "text"
    end
  end

  # Format completion item for LSP
  defp format_completion_item(%{text: text, label: label, kind: kind}) do
    %{
      "label" => label || text,
      "kind" => kind || 1,
      "detail" => "AI suggestion",
      "insertText" => text,
      "insertTextFormat" => 1
    }
  end

  defp format_completion_item(text) when is_binary(text) do
    %{
      "label" => text,
      "kind" => 1,
      "insertText" => text,
      "insertTextFormat" => 1
    }
  end

  # Format location for LSP
  defp format_location(%{uri: uri, range: range}) do
    %{
      "uri" => uri,
      "range" => range
    }
  end

  defp format_location(%{file: file, line: line, column: column}) do
    %{
      "uri" => "file://#{file}",
      "range" => %{
        "start" => %{"line" => line - 1, "character" => column - 1},
        "end" => %{"line" => line - 1, "character" => column}
      }
    }
  end

  # Format document symbol
  defp format_document_symbol(%{name: name, kind: kind, range: range}) do
    %{
      "name" => name,
      "kind" => kind,
      "range" => range,
      "selectionRange" => range
    }
  end

  # Format workspace symbol
  defp format_workspace_symbol(%{name: name, kind: kind, location: location}) do
    %{
      "name" => name,
      "kind" => kind,
      "location" => format_location(location)
    }
  end

  # Format diagnostics
  defp format_diagnostics(diagnostics) when is_list(diagnostics) do
    Enum.map(diagnostics, &format_diagnostic/1)
  end

  defp format_diagnostics(_), do: []

  defp format_diagnostic(%{
         severity: severity,
         message: message,
         line: line,
         column: column,
         end_line: end_line,
         end_column: end_column
       }) do
    %{
      "range" => %{
        "start" => %{"line" => line - 1, "character" => column - 1},
        "end" => %{"line" => (end_line || line) - 1, "character" => (end_column || column) - 1}
      },
      "severity" => map_severity(severity),
      "message" => message,
      "source" => "lang"
    }
  end

  defp map_severity(:error), do: 1
  defp map_severity(:warning), do: 2
  defp map_severity(:info), do: 3
  defp map_severity(:hint), do: 4
  defp map_severity(_), do: 3

  # Command implementations
  defp analyze_file_command(uri, state) do
    case Map.get(state.documents, uri) do
      nil ->
        {:error, "Document not found"}

      document ->
        format = extract_format_from_uri(uri)

        case Lang.TextIntelligence.AnalysisEngine.analyze_content(document.text, format) do
          {:ok, analysis} ->
            {:ok,
             %{
               "complexity" => analysis[:complexity] || "unknown",
               "issues" => length(analysis[:diagnostics] || []),
               "suggestions" => analysis[:suggestions] || []
             }}

          {:error, reason} ->
            {:error, "Analysis failed: #{inspect(reason)}"}
        end
    end
  end

  defp generate_completion_command(uri, position, state) do
    case Map.get(state.documents, uri) do
      nil ->
        {:error, "Document not found"}

      document ->
        context = get_completion_context(document.text, position)

        case Lang.Providers.Router.route_lsp(:completion, %{
               context: context,
               language: document.language_id,
               max_tokens: 100
             }) do
          {:ok, completions} ->
            {:ok, %{"completions" => completions}}

          {:error, reason} ->
            {:error, "Generation failed: #{inspect(reason)}"}
        end
    end
  end

  defp explain_code_command(uri, range, state) do
    case Map.get(state.documents, uri) do
      nil ->
        {:error, "Document not found"}

      document ->
        code_snippet = extract_text_in_range(document.text, range)

        case Lang.Providers.Router.route_lsp(:explain, %{
               code: code_snippet,
               language: document.language_id
             }) do
          {:ok, explanation} ->
            {:ok, %{"explanation" => explanation}}

          {:error, reason} ->
            {:error, "Explanation failed: #{inspect(reason)}"}
        end
    end
  end

  defp refactor_code_command(uri, range, refactor_type, state) do
    case Map.get(state.documents, uri) do
      nil ->
        {:error, "Document not found"}

      document ->
        code_snippet = extract_text_in_range(document.text, range)

        case Lang.Providers.Router.route_lsp(:refactor, %{
               code: code_snippet,
               type: refactor_type,
               language: document.language_id
             }) do
          {:ok, refactored} ->
            {:ok, %{"refactored" => refactored}}

          {:error, reason} ->
            {:error, "Refactoring failed: #{inspect(reason)}"}
        end
    end
  end

  defp generate_tests_command(uri, range, state) do
    case Map.get(state.documents, uri) do
      nil ->
        {:error, "Document not found"}

      document ->
        code_snippet = extract_text_in_range(document.text, range)

        case Lang.Providers.Router.route_lsp(:generate_tests, %{
               code: code_snippet,
               language: document.language_id
             }) do
          {:ok, tests} ->
            {:ok, %{"tests" => tests}}

          {:error, reason} ->
            {:error, "Test generation failed: #{inspect(reason)}"}
        end
    end
  end

  defp extract_text_in_range(text, %{"start" => start_pos, "end" => end_pos}) do
    lines = String.split(text, "\n")

    start_line = start_pos["line"]
    start_char = start_pos["character"]
    end_line = end_pos["line"]
    end_char = end_pos["character"]

    if start_line == end_line do
      # Single line selection
      line = Enum.at(lines, start_line, "")
      String.slice(line, start_char, end_char - start_char)
    else
      # Multi-line selection
      selected_lines = Enum.slice(lines, start_line..end_line)

      selected_lines
      |> Enum.with_index()
      |> Enum.map(fn {line, idx} ->
        cond do
          idx == 0 -> String.slice(line, start_char..-1)
          idx == length(selected_lines) - 1 -> String.slice(line, 0, end_char)
          true -> line
        end
      end)
      |> Enum.join("\n")
    end
  end
end
