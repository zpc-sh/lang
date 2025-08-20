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

    # In a real implementation, this would start a TCP/JSON-RPC server
    # For now, we'll track connections and provide LSP-style methods
    {:ok,
     %{
       port: port,
       connections: %{},
       documents: %{},
       capabilities: build_server_capabilities()
     }}
  end

  def handle_completion_request(uri, position, context) do
    GenServer.call(__MODULE__, {:completion, uri, position, context})
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
end
