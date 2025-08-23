defmodule Lang.LSP.Server do
  @moduledoc """
  Language Server Protocol implementation for universal text intelligence
  """

  use GenServer
  require Logger

  alias Lang.TextIntelligence.AnalysisEngine

  def start_link(opts) do
    port = Keyword.get(opts, :port, 4001)
    GenServer.start_link(__MODULE__, %{port: port}, name: __MODULE__)
  end

  @impl true
  def init(%{port: port}) do
    Logger.info("Starting LSP server on port #{port}")

    # Start TCP server
    case :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true]) do
      {:ok, listen_socket} ->
        Logger.info("LSP TCP server listening on port #{port}")

        # Start accepting connections in a separate task
        Task.start_link(fn -> accept_connections(listen_socket) end)

        {:ok,
         %{
           port: port,
           listen_socket: listen_socket,
           connections: %{},
           documents: %{},
           capabilities: build_server_capabilities(),
           next_id: 1
         }}

      {:error, reason} ->
        Logger.error("Failed to start LSP server: #{reason}")
        {:stop, {:tcp_error, reason}}
    end
  end

  defp accept_connections(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        Logger.info("New LSP client connected")
        # Handle each connection in a separate process
        Task.start_link(fn -> handle_connection(socket) end)
        accept_connections(listen_socket)

      {:error, reason} ->
        Logger.error("Failed to accept connection: #{reason}")
        :timer.sleep(1000)
        accept_connections(listen_socket)
    end
  end

  defp handle_connection(socket) do
    case receive_message(socket) do
      {:ok, message} ->
        response = process_lsp_message(message)
        send_response(socket, response)
        handle_connection(socket)

      {:error, :closed} ->
        Logger.info("LSP client disconnected")
        :gen_tcp.close(socket)

      {:error, reason} ->
        Logger.error("LSP connection error: #{reason}")
        :gen_tcp.close(socket)
    end
  end

  defp receive_message(socket) do
    # Read Content-Length header first
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        parse_lsp_message(data)

      {:error, :closed} ->
        {:error, :closed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_lsp_message(raw_data) do
    # Parse LSP message format: Content-Length header + JSON content
    case String.split(raw_data, "\r\n\r\n", parts: 2) do
      [headers, content] ->
        case extract_content_length(headers) do
          {:ok, length} when byte_size(content) >= length ->
            json_content = binary_part(content, 0, length)

            case Jason.decode(json_content) do
              {:ok, message} -> {:ok, message}
              {:error, reason} -> {:error, {:json_decode, reason}}
            end

          {:ok, _length} ->
            {:error, :incomplete_message}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  defp extract_content_length(headers) do
    case Regex.run(~r/Content-Length:\s*(\d+)/i, headers) do
      [_, length_str] ->
        case Integer.parse(length_str) do
          {length, ""} -> {:ok, length}
          _ -> {:error, :invalid_content_length}
        end

      nil ->
        {:error, :missing_content_length}
    end
  end

  defp process_lsp_message(message) do
    case message do
      %{"method" => "initialize", "id" => id, "params" => params} ->
        handle_initialize(id, params)

      %{"method" => "textDocument/didOpen", "params" => params} ->
        handle_did_open(params)

      %{"method" => "textDocument/completion", "id" => id, "params" => params} ->
        handle_completion(id, params)

      %{"method" => "textDocument/hover", "id" => id, "params" => params} ->
        handle_hover(id, params)

      %{"method" => "textDocument/didChange", "params" => params} ->
        handle_did_change(params)

      %{"method" => "shutdown", "id" => id} ->
        handle_shutdown(id)

      %{"method" => method} ->
        Logger.info("Unhandled LSP method: #{method}")
        nil

      _ ->
        Logger.warning("Invalid LSP message format")
        nil
    end
  end

  defp send_response(socket, nil), do: :ok

  defp send_response(socket, response) do
    json_content = Jason.encode!(response)
    content_length = byte_size(json_content)

    message = "Content-Length: #{content_length}\r\n\r\n#{json_content}"
    :gen_tcp.send(socket, message)
  end

  defp handle_initialize(id, params) do
    Logger.info("LSP Initialize request received")

    capabilities = build_server_capabilities()

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "capabilities" => capabilities,
        "serverInfo" => %{
          "name" => "LANG LSP Server",
          "version" => "1.0.0"
        }
      }
    }
  end

  defp handle_did_open(params) do
    uri = params["textDocument"]["uri"]
    content = params["textDocument"]["text"]

    # Store document content
    GenServer.cast(__MODULE__, {:store_document, uri, content})

    # Send diagnostics
    diagnostics = analyze_document(content)
    send_diagnostics(uri, diagnostics)

    nil
  end

  defp handle_completion(id, params) do
    uri = params["textDocument"]["uri"]
    position = params["position"]

    # Get document content
    content = GenServer.call(__MODULE__, {:get_document, uri})
    completions = generate_completions(content, position)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "isIncomplete" => false,
        "items" => completions
      }
    }
  end

  defp handle_hover(id, params) do
    uri = params["textDocument"]["uri"]
    position = params["position"]

    content = GenServer.call(__MODULE__, {:get_document, uri})
    hover_info = generate_hover_info(content, position)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => hover_info
    }
  end

  defp handle_did_change(params) do
    uri = params["textDocument"]["uri"]
    changes = params["contentChanges"]

    # Update document content
    GenServer.cast(__MODULE__, {:update_document, uri, changes})

    # Send updated diagnostics
    updated_content = GenServer.call(__MODULE__, {:get_document, uri})
    diagnostics = analyze_document(updated_content)
    send_diagnostics(uri, diagnostics)

    nil
  end

  defp handle_shutdown(id) do
    Logger.info("LSP Shutdown request received")

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => nil
    }
  end

  def handle_completion_request(uri, position, context) do
    GenServer.call(__MODULE__, {:completion, uri, position, context})
  end

  defp analyze_document(content) do
    # Use the UniversalParser for document analysis
    case Kyozo.Lang.UniversalParser.parse(content) do
      {:ok, document} ->
        generate_diagnostics_from_document(document)

      {:error, _reason} ->
        []
    end
  end

  defp generate_diagnostics_from_document(document) do
    diagnostics = []

    # Check for parsing errors
    diagnostics =
      if document.parsed == nil do
        [create_diagnostic(0, 0, "Document parsing failed", :error) | diagnostics]
      else
        diagnostics
      end

    # Check complexity
    diagnostics =
      case document.analysis do
        %{complexity_score: score} when score > 8.0 ->
          [
            create_diagnostic(0, 0, "Document complexity is high (#{score})", :warning)
            | diagnostics
          ]

        _ ->
          diagnostics
      end

    # Check readability
    diagnostics =
      case document.analysis do
        %{readability_score: score} when score < 3.0 ->
          [create_diagnostic(0, 0, "Document readability is low (#{score})", :info) | diagnostics]

        _ ->
          diagnostics
      end

    diagnostics
  end

  defp create_diagnostic(line, character, message, severity) do
    severity_num =
      case severity do
        :error -> 1
        :warning -> 2
        :info -> 3
        :hint -> 4
      end

    %{
      "range" => %{
        "start" => %{"line" => line, "character" => character},
        "end" => %{"line" => line, "character" => character + 10}
      },
      "severity" => severity_num,
      "message" => message,
      "source" => "lang-lsp"
    }
  end

  defp generate_completions(content, position) do
    line_num = position["line"]
    char_pos = position["character"]

    lines = String.split(content, "\n")
    current_line = Enum.at(lines, line_num, "")

    # Simple word-based completions
    words = String.split(content) |> Enum.uniq() |> Enum.filter(&(String.length(&1) > 2))

    Enum.map(words, fn word ->
      %{
        "label" => word,
        # Text
        "kind" => 1,
        "insertText" => word
      }
    end)
    |> Enum.take(20)
  end

  defp generate_hover_info(content, position) do
    line_num = position["line"]

    lines = String.split(content, "\n")
    current_line = Enum.at(lines, line_num, "")

    if String.trim(current_line) != "" do
      %{
        "contents" => [
          %{
            "language" => "text",
            "value" => "Line #{line_num + 1}: #{String.trim(current_line)}"
          }
        ]
      }
    else
      nil
    end
  end

  defp send_diagnostics(uri, diagnostics) do
    # This would send diagnostics to all connected clients
    # For now, just log them
    Logger.info("Sending diagnostics", uri: uri, count: length(diagnostics))
  end

  def handle_hover_request(uri, position) do
    GenServer.call(__MODULE__, {:hover, uri, position})
  end

  def handle_diagnostics_request(uri, content) do
    GenServer.call(__MODULE__, {:diagnostics, uri, content})
  end

  def handle_document_open(uri, content, language_id) do
    GenServer.call(__MODULE__, {:document_open, uri, content, language_id})
  end

  def handle_document_change(uri, changes) do
    GenServer.call(__MODULE__, {:document_change, uri, changes})
  end

  def handle_document_close(uri) do
    GenServer.call(__MODULE__, {:document_close, uri})
  end

  def get_server_info do
    GenServer.call(__MODULE__, :server_info)
  end

  @impl true
  def handle_call({:completion, uri, position, context}, _from, state) do
    Logger.info("LSP completion request", uri: uri, position: position)

    case Map.get(state.documents, uri) do
      nil ->
        {:reply, empty_completion_response(), state}

      document ->
        completions = generate_completions(document, position, context)
        {:reply, completions, state}
    end
  end

  @impl true
  def handle_call({:hover, uri, position}, _from, state) do
    Logger.info("LSP hover request", uri: uri, position: position)

    case Map.get(state.documents, uri) do
      nil ->
        {:reply, nil, state}

      document ->
        hover_info = generate_hover_info(document, position)
        {:reply, hover_info, state}
    end
  end

  @impl true
  def handle_call({:diagnostics, uri, content}, _from, state) do
    Logger.info("LSP diagnostics request", uri: uri)

    # Determine format from URI extension
    format = extract_format_from_uri(uri)

    case AnalysisEngine.analyze_content(content, format) do
      {:ok, analysis} ->
        diagnostics = convert_to_lsp_diagnostics(analysis.diagnostics)
        {:reply, diagnostics, state}

      {:error, _reason} ->
        {:reply, [], state}
    end
  end

  @impl true
  def handle_call({:document_open, uri, content, language_id}, _from, state) do
    Logger.info("LSP document opened", uri: uri, language_id: language_id)

    document = %{
      uri: uri,
      content: content,
      language_id: language_id,
      version: 1,
      opened_at: DateTime.utc_now()
    }

    # Perform initial analysis
    case AnalysisEngine.analyze_content(content, language_id) do
      {:ok, analysis} ->
        updated_document = Map.put(document, :analysis, analysis)
        documents = Map.put(state.documents, uri, updated_document)

        # Send diagnostics
        diagnostics = convert_to_lsp_diagnostics(analysis.diagnostics)
        send_diagnostics(uri, diagnostics)

        {:reply, :ok, %{state | documents: documents}}

      {:error, _reason} ->
        documents = Map.put(state.documents, uri, document)
        {:reply, :ok, %{state | documents: documents}}
    end
  end

  @impl true
  def handle_call({:document_change, uri, changes}, _from, state) do
    Logger.info("LSP document changed", uri: uri, changes: length(changes))

    case Map.get(state.documents, uri) do
      nil ->
        {:reply, {:error, :document_not_found}, state}

      document ->
        updated_content = apply_changes(document.content, changes)

        updated_document = %{
          document
          | content: updated_content,
            version: document.version + 1,
            modified_at: DateTime.utc_now()
        }

        # Re-analyze content
        case AnalysisEngine.analyze_content(updated_content, document.language_id) do
          {:ok, analysis} ->
            final_document = Map.put(updated_document, :analysis, analysis)
            documents = Map.put(state.documents, uri, final_document)

            # Send updated diagnostics
            diagnostics = convert_to_lsp_diagnostics(analysis.diagnostics)
            send_diagnostics(uri, diagnostics)

            {:reply, :ok, %{state | documents: documents}}

          {:error, _reason} ->
            documents = Map.put(state.documents, uri, updated_document)
            {:reply, :ok, %{state | documents: documents}}
        end
    end
  end

  @impl true
  def handle_call({:document_close, uri}, _from, state) do
    Logger.info("LSP document closed", uri: uri)

    documents = Map.delete(state.documents, uri)
    {:reply, :ok, %{state | documents: documents}}
  end

  @impl true
  def handle_call(:server_info, _from, state) do
    info = %{
      name: "LANG LSP Server",
      version: "1.0.0",
      port: state.port,
      active_documents: map_size(state.documents),
      capabilities: state.capabilities,
      uptime: :erlang.system_time(:second)
    }

    {:reply, info, state}
  end

  # Private helper functions

  defp build_server_capabilities do
    %{
      "textDocumentSync" => %{
        "openClose" => true,
        # Incremental changes
        "change" => 2,
        "save" => %{"includeText" => false}
      },
      "completionProvider" => %{
        "triggerCharacters" => ["."],
        "resolveProvider" => false
      },
      "hoverProvider" => true,
      "diagnosticProvider" => %{
        "interFileDependencies" => false,
        "workspaceDiagnostics" => false
      },
      "documentFormattingProvider" => true,
      "documentRangeFormattingProvider" => true,
      "documentHighlightProvider" => true,
      "workspaceSymbolProvider" => true,
      "definitionProvider" => false,
      "referencesProvider" => false,
      "renameProvider" => false
    }
  end

  defp generate_completions(document, position, _context) do
    case Map.get(document, :analysis) do
      nil ->
        empty_completion_response()

      analysis ->
        # Convert our analysis completions to LSP format
        items =
          Enum.map(analysis.completions, fn completion ->
            %{
              "label" => completion.label,
              "kind" => completion_kind_to_lsp(completion.kind),
              "detail" => completion.detail,
              "insertText" => completion.insert_text,
              "documentation" => %{
                "kind" => "markdown",
                "value" => completion.detail
              }
            }
          end)

        # Add context-aware completions based on position
        contextual_items = generate_contextual_completions(document, position)

        %{
          "isIncomplete" => false,
          "items" => items ++ contextual_items
        }
    end
  end

  defp generate_contextual_completions(document, position) do
    # Generate completions based on current cursor position
    case document.language_id do
      "markdown" -> generate_markdown_completions(document, position)
      "javascript" -> generate_javascript_completions(document, position)
      "python" -> generate_python_completions(document, position)
      "elixir" -> generate_elixir_completions(document, position)
      _ -> []
    end
  end

  defp generate_markdown_completions(_document, _position) do
    [
      %{
        "label" => "## Header 2",
        # Keyword
        "kind" => 12,
        "insertText" => "## ${1:Header}",
        # Snippet
        "insertTextFormat" => 2
      },
      %{
        "label" => "[Link](url)",
        "kind" => 12,
        "insertText" => "[${1:text}](${2:url})",
        "insertTextFormat" => 2
      },
      %{
        "label" => "```code block```",
        "kind" => 12,
        "insertText" => "```${1:language}\n${2:code}\n```",
        "insertTextFormat" => 2
      }
    ]
  end

  defp generate_javascript_completions(_document, _position) do
    [
      %{
        "label" => "console.log()",
        # Method
        "kind" => 2,
        "insertText" => "console.log(${1:value});",
        "insertTextFormat" => 2
      },
      %{
        "label" => "function",
        "kind" => 12,
        "insertText" => "function ${1:name}(${2:params}) {\n\t${3:body}\n}",
        "insertTextFormat" => 2
      }
    ]
  end

  defp generate_python_completions(_document, _position) do
    [
      %{
        "label" => "print()",
        "kind" => 2,
        "insertText" => "print(${1:value})",
        "insertTextFormat" => 2
      },
      %{
        "label" => "def function",
        "kind" => 12,
        "insertText" => "def ${1:name}(${2:args}):\n\t${3:body}",
        "insertTextFormat" => 2
      }
    ]
  end

  defp generate_elixir_completions(_document, _position) do
    [
      %{
        "label" => "IO.puts",
        "kind" => 2,
        "insertText" => "IO.puts(${1:value})",
        "insertTextFormat" => 2
      },
      %{
        "label" => "def function",
        "kind" => 12,
        "insertText" => "def ${1:name}(${2:args}) do\n\t${3:body}\nend",
        "insertTextFormat" => 2
      }
    ]
  end

  defp generate_hover_info(document, position) do
    case Map.get(document, :analysis) do
      nil ->
        nil

      analysis ->
        # Generate hover content based on analysis
        content = build_hover_content(analysis, position)

        %{
          "contents" => %{
            "kind" => "markdown",
            "value" => content
          },
          "range" => build_hover_range(position)
        }
    end
  end

  defp build_hover_content(analysis, _position) do
    """
    ## LANG Analysis Results

    **Format:** #{analysis.format}
    **Content Size:** #{analysis.content_size} bytes
    **Complexity Score:** #{analysis.analysis.complexity_score}/10
    **Readability Score:** #{analysis.analysis.readability_score}/10
    **Structure Quality:** #{analysis.analysis.structure_quality}/10

    ### Suggestions
    #{Enum.map_join(analysis.analysis.suggestions, "\n", &"- #{&1}")}

    *Analysis performed at #{Calendar.strftime(analysis.timestamp, "%Y-%m-%d %H:%M:%S")} UTC*
    """
  end

  defp build_hover_range(position) do
    %{
      "start" => position,
      "end" => %{
        "line" => position["line"],
        "character" => position["character"] + 10
      }
    }
  end

  defp convert_to_lsp_diagnostics(diagnostics) when is_list(diagnostics) do
    Enum.map(diagnostics, &convert_diagnostic/1)
  end

  defp convert_to_lsp_diagnostics(_), do: []

  defp convert_diagnostic(diagnostic) do
    %{
      "range" => diagnostic.range,
      "severity" => severity_to_lsp(diagnostic.severity),
      "message" => diagnostic.message,
      "source" => "lang"
    }
  end

  defp severity_to_lsp(:error), do: 1
  defp severity_to_lsp(:warning), do: 2
  defp severity_to_lsp(:info), do: 3
  defp severity_to_lsp(:hint), do: 4
  defp severity_to_lsp(_), do: 3

  defp completion_kind_to_lsp(:text), do: 1
  defp completion_kind_to_lsp(:method), do: 2
  defp completion_kind_to_lsp(:function), do: 3
  defp completion_kind_to_lsp(:constructor), do: 4
  defp completion_kind_to_lsp(:field), do: 5
  defp completion_kind_to_lsp(:variable), do: 6
  defp completion_kind_to_lsp(:class), do: 7
  defp completion_kind_to_lsp(:interface), do: 8
  defp completion_kind_to_lsp(:module), do: 9
  defp completion_kind_to_lsp(:property), do: 10
  defp completion_kind_to_lsp(:unit), do: 11
  defp completion_kind_to_lsp(:value), do: 12
  defp completion_kind_to_lsp(:enum), do: 13
  defp completion_kind_to_lsp(:keyword), do: 14
  defp completion_kind_to_lsp(:snippet), do: 15
  defp completion_kind_to_lsp(:suggestion), do: 24
  defp completion_kind_to_lsp(_), do: 1

  defp extract_format_from_uri(uri) do
    case Path.extname(uri) do
      ".md" -> "markdown"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      ".py" -> "python"
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".json" -> "json"
      ".yaml" -> "yaml"
      ".yml" -> "yaml"
      ".sql" -> "sql"
      ".txt" -> "text"
      _ -> "text"
    end
  end

  defp empty_completion_response do
    %{
      "isIncomplete" => false,
      "items" => []
    }
  end

  defp apply_changes(content, changes) do
    # Apply incremental changes to document content
    # This is a simplified implementation - real LSP would handle ranges properly
    Enum.reduce(changes, content, fn change, acc ->
      case change do
        # Full document replace
        %{"text" => new_text} -> new_text
        # Skip unsupported change types for now
        _ -> acc
      end
    end)
  end

  defp send_diagnostics(uri, diagnostics) do
    # In a real LSP implementation, this would send diagnostics via JSON-RPC
    # For now, we'll just log them
    Logger.info("Sending diagnostics", uri: uri, count: length(diagnostics))

    # You could implement actual JSON-RPC notification sending here
    # Phoenix.PubSub.broadcast(Lang.PubSub, "lsp_diagnostics", {:diagnostics, uri, diagnostics})
  end

  # TCP Message Handling Functions

  defp receive_message(socket) do
    # LSP uses Content-Length header for message framing
    case read_headers(socket) do
      {:ok, headers} ->
        content_length = parse_content_length(headers)
        read_content(socket, content_length)

      error ->
        error
    end
  end

  defp read_headers(socket, acc \\ "") do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        acc = acc <> data

        # Check for end of headers (\r\n\r\n)
        if String.contains?(acc, "\r\n\r\n") do
          [headers, _rest] = String.split(acc, "\r\n\r\n", parts: 2)
          {:ok, headers}
        else
          read_headers(socket, acc)
        end

      {:error, :closed} ->
        {:error, :closed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_content_length(headers) do
    headers
    |> String.split("\r\n")
    |> Enum.find_value(0, fn line ->
      case String.split(line, ": ", parts: 2) do
        ["Content-Length", length] -> String.to_integer(length)
        _ -> nil
      end
    end)
  end

  defp read_content(socket, length) do
    case :gen_tcp.recv(socket, length) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, message} -> {:ok, message}
          {:error, _} -> {:error, :invalid_json}
        end

      error ->
        error
    end
  end

  defp process_lsp_message(%{"method" => method} = message) do
    id = Map.get(message, "id")
    params = Map.get(message, "params", %{})

    response =
      case method do
        "initialize" ->
          handle_initialize(params)

        "initialized" ->
          # Client notification that initialization is complete
          nil

        "shutdown" ->
          %{"result" => nil}

        "textDocument/didOpen" ->
          handle_did_open(params)
          nil

        "textDocument/didChange" ->
          handle_did_change(params)
          nil

        "textDocument/didClose" ->
          handle_did_close(params)
          nil

        "textDocument/completion" ->
          handle_completion(params)

        "textDocument/hover" ->
          handle_hover(params)

        "textDocument/publishDiagnostics" ->
          handle_publish_diagnostics(params)

        _ ->
          %{"error" => %{"code" => -32601, "message" => "Method not found"}}
      end

    if id && response do
      Map.merge(%{"jsonrpc" => "2.0", "id" => id}, response)
    else
      response
    end
  end

  defp process_lsp_message(_), do: nil

  defp send_response(socket, nil), do: :ok

  defp send_response(socket, response) do
    json = Jason.encode!(response)
    content_length = byte_size(json)

    message = "Content-Length: #{content_length}\r\n\r\n#{json}"
    :gen_tcp.send(socket, message)
  end

  # LSP Request Handlers

  defp handle_initialize(params) do
    capabilities = build_server_capabilities()

    %{
      "result" => %{
        "capabilities" => capabilities,
        "serverInfo" => %{
          "name" => "LANG LSP Server",
          "version" => "1.0.0"
        }
      }
    }
  end

  defp handle_did_open(%{"textDocument" => doc}) do
    handle_document_open(
      doc["uri"],
      doc["text"],
      doc["languageId"]
    )
  end

  defp handle_did_change(%{"textDocument" => doc, "contentChanges" => changes}) do
    handle_document_change(doc["uri"], changes)
  end

  defp handle_did_close(%{"textDocument" => doc}) do
    handle_document_close(doc["uri"])
  end

  defp handle_completion(%{"textDocument" => doc, "position" => position} = params) do
    context = Map.get(params, "context", %{})
    completions = handle_completion_request(doc["uri"], position, context)

    %{"result" => completions}
  end

  defp handle_hover(%{"textDocument" => doc, "position" => position}) do
    hover = handle_hover_request(doc["uri"], position)

    %{"result" => hover}
  end

  defp handle_publish_diagnostics(%{"textDocument" => doc}) do
    diagnostics = handle_diagnostics_request(doc["uri"], doc["text"])

    # Send diagnostics as a notification
    notification = %{
      "jsonrpc" => "2.0",
      "method" => "textDocument/publishDiagnostics",
      "params" => %{
        "uri" => doc["uri"],
        "diagnostics" => diagnostics
      }
    }

    # This would be sent back through the socket
    notification
  end

  # Streaming Support for Large Responses

  defp send_streaming_response(socket, response, chunk_size \\ 8192) do
    json = Jason.encode!(response)

    if byte_size(json) > chunk_size do
      # For very large responses, we can send in chunks
      # This is still within the LSP protocol as we send complete messages
      send_response(socket, response)
    else
      send_response(socket, response)
    end
  end

  # Connection Management

  @impl true
  def handle_info({:tcp_closed, socket}, state) do
    Logger.info("LSP client disconnected")
    connections = Map.delete(state.connections, socket)
    {:noreply, %{state | connections: connections}}
  end

  @impl true
  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.error("LSP TCP error: #{inspect(reason)}")
    connections = Map.delete(state.connections, socket)
    {:noreply, %{state | connections: connections}}
  end
end
