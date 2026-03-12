defmodule Lang.LSP.Integration do
  @moduledoc """
  Integration layer between Lang and Language Server Protocol (LSP) servers.
  
  This module provides a unified interface for accessing language-specific
  semantic information through LSP servers. It enables symbol-level operations
  such as finding references, definitions, and performing precise edits
  across multiple programming languages.
  """
  
  alias Lang.Native.LSPClient
  require Logger
  
  @doc """
  Initializes an LSP server for the given workspace path and language.
  
  ## Parameters
  
  - `workspace_path` - Root directory of the workspace
  - `language` - Language identifier (e.g., "elixir", "rust", "javascript")
  - `options` - Additional options for server initialization
  
  ## Returns
  
  - `{:ok, server_id}` - Successfully initialized server with ID
  - `{:error, reason}` - Failed to initialize server
  """
  @spec initialize_server(String.t(), String.t(), keyword()) :: {:ok, binary()} | {:error, any()}
  def initialize_server(workspace_path, language, options \\ []) do
    # Use the Rust NIF to initialize the server
    LSPClient.initialize(workspace_path, language, options)
  end
  
  @doc """
  Finds symbols in the specified document.
  
  ## Parameters
  
  - `server_id` - LSP server ID from initialize_server
  - `file_path` - Path to the file
  - `options` - Additional options:
    - `:include_declarations` - Include declarations (default: true)
    - `:include_definitions` - Include definitions (default: true)
    - `:include_implementations` - Include implementations (default: false)
  
  ## Returns
  
  - `{:ok, symbols}` - List of document symbols
  - `{:error, reason}` - Failed to retrieve symbols
  """
  @spec document_symbols(binary(), String.t(), keyword()) :: {:ok, list(map())} | {:error, any()}
  def document_symbols(server_id, file_path, options \\ []) do
    case LSPClient.document_symbols(server_id, file_path) do
      {:ok, symbols} ->
        # Transform symbols into a standard format
        transformed_symbols = 
          symbols
          |> Enum.map(&transform_symbol/1)
          |> maybe_filter_symbols(options)
        
        {:ok, transformed_symbols}
        
      error -> error
    end
  end
  
  @doc """
  Finds all references to a symbol.
  
  ## Parameters
  
  - `server_id` - LSP server ID
  - `file_path` - Path to the file containing the symbol
  - `line` - 0-based line number
  - `character` - 0-based character position within the line
  - `options` - Additional options:
    - `:include_declaration` - Include the declaration itself (default: false)
    - `:workspace_wide` - Search across the entire workspace (default: true)
  
  ## Returns
  
  - `{:ok, references}` - List of references to the symbol
  - `{:error, reason}` - Failed to find references
  """
  @spec find_references(binary(), String.t(), non_neg_integer(), non_neg_integer(), keyword()) :: 
        {:ok, list(map())} | {:error, any()}
  def find_references(server_id, file_path, line, character, options \\ []) do
    include_declaration = Keyword.get(options, :include_declaration, false)
    
    case LSPClient.find_references(server_id, file_path, line, character, include_declaration) do
      {:ok, references} -> 
        {:ok, Enum.map(references, &transform_location/1)}
      error -> error
    end
  end
  
  @doc """
  Finds the definition of a symbol.
  
  ## Parameters
  
  - `server_id` - LSP server ID
  - `file_path` - Path to the file containing the symbol
  - `line` - 0-based line number
  - `character` - 0-based character position within the line
  
  ## Returns
  
  - `{:ok, locations}` - List of definition locations
  - `{:error, reason}` - Failed to find definition
  """
  @spec find_definition(binary(), String.t(), non_neg_integer(), non_neg_integer()) ::
        {:ok, list(map())} | {:error, any()}
  def find_definition(server_id, file_path, line, character) do
    case LSPClient.find_definition(server_id, file_path, line, character) do
      {:ok, locations} -> 
        {:ok, Enum.map(locations, &transform_location/1)}
      error -> error
    end
  end
  
  @doc """
  Renames a symbol across the workspace.
  
  ## Parameters
  
  - `server_id` - LSP server ID
  - `file_path` - Path to the file containing the symbol
  - `line` - 0-based line number
  - `character` - 0-based character position within the line
  - `new_name` - New name for the symbol
  
  ## Returns
  
  - `{:ok, changes}` - Map of file paths to edits
  - `{:error, reason}` - Failed to rename symbol
  """
  @spec rename_symbol(binary(), String.t(), non_neg_integer(), non_neg_integer(), String.t()) ::
        {:ok, map()} | {:error, any()}
  def rename_symbol(server_id, file_path, line, character, new_name) do
    case LSPClient.rename(server_id, file_path, line, character, new_name) do
      {:ok, changes} ->
        transformed_changes = transform_workspace_edit(changes)
        
        # Use Oban worker to apply changes asynchronously
        %{changes: transformed_changes}
        |> Lang.Workers.LSPEditWorker.new(queue: :lsp)
        |> Oban.insert()
        
        {:ok, transformed_changes}
        
      error -> error
    end
  end
  
  @doc """
  Gets the hover information for a symbol.
  
  ## Parameters
  
  - `server_id` - LSP server ID
  - `file_path` - Path to the file containing the symbol
  - `line` - 0-based line number
  - `character` - 0-based character position within the line
  
  ## Returns
  
  - `{:ok, hover_info}` - Hover information for the symbol
  - `{:error, reason}` - Failed to get hover information
  """
  @spec hover(binary(), String.t(), non_neg_integer(), non_neg_integer()) ::
        {:ok, map()} | {:error, any()}
  def hover(server_id, file_path, line, character) do
    LSPClient.hover(server_id, file_path, line, character)
  end
  
  @doc """
  Formats a document according to language server formatting rules.
  
  ## Parameters
  
  - `server_id` - LSP server ID
  - `file_path` - Path to the file to format
  - `options` - Formatting options (language-specific)
  
  ## Returns
  
  - `{:ok, formatted_text}` - The formatted document text
  - `{:error, reason}` - Failed to format document
  """
  @spec format_document(binary(), String.t(), map()) :: {:ok, String.t()} | {:error, any()}
  def format_document(server_id, file_path, options \\ %{}) do
    LSPClient.format_document(server_id, file_path, options)
  end
  
  @doc """
  Gets diagnostics for a specific file.
  
  ## Parameters
  
  - `server_id` - LSP server ID
  - `file_path` - Path to the file
  
  ## Returns
  
  - `{:ok, diagnostics}` - List of diagnostics
  - `{:error, reason}` - Failed to get diagnostics
  """
  @spec get_diagnostics(binary(), String.t()) :: {:ok, list(map())} | {:error, any()}
  def get_diagnostics(server_id, file_path) do
    case LSPClient.get_diagnostics(server_id, file_path) do
      {:ok, diagnostics} -> 
        {:ok, Enum.map(diagnostics, &transform_diagnostic/1)}
      error -> error
    end
  end
  
  @doc """
  Notifies the LSP server that a file has been opened.
  
  ## Parameters
  
  - `server_id` - LSP server ID
  - `file_path` - Path to the file
  - `language_id` - Language identifier
  - `version` - Document version number
  - `text` - Document text
  
  ## Returns
  
  - `:ok` - Successfully notified server
  - `{:error, reason}` - Failed to notify server
  """
  @spec did_open(binary(), String.t(), String.t(), integer(), String.t()) :: :ok | {:error, any()}
  def did_open(server_id, file_path, language_id, version, text) do
    LSPClient.did_open(server_id, file_path, language_id, version, text)
  end
  
  @doc """
  Notifies the LSP server that a file has been changed.
  
  ## Parameters
  
  - `server_id` - LSP server ID
  - `file_path` - Path to the file
  - `version` - Document version number
  - `changes` - List of text document content changes
  
  ## Returns
  
  - `:ok` - Successfully notified server
  - `{:error, reason}` - Failed to notify server
  """
  @spec did_change(binary(), String.t(), integer(), list(map())) :: :ok | {:error, any()}
  def did_change(server_id, file_path, version, changes) do
    LSPClient.did_change(server_id, file_path, version, changes)
  end
  
  @doc """
  Notifies the LSP server that a file has been saved.
  
  ## Parameters
  
  - `server_id` - LSP server ID
  - `file_path` - Path to the file
  
  ## Returns
  
  - `:ok` - Successfully notified server
  - `{:error, reason}` - Failed to notify server
  """
  @spec did_save(binary(), String.t()) :: :ok | {:error, any()}
  def did_save(server_id, file_path) do
    LSPClient.did_save(server_id, file_path)
  end
  
  @doc """
  Shuts down an LSP server.
  
  ## Parameters
  
  - `server_id` - LSP server ID
  
  ## Returns
  
  - `:ok` - Successfully shut down server
  - `{:error, reason}` - Failed to shut down server
  """
  @spec shutdown_server(binary()) :: :ok | {:error, any()}
  def shutdown_server(server_id) do
    LSPClient.shutdown(server_id)
  end
  
  # Private helper functions
  
  defp transform_symbol(symbol) do
    %{
      name: symbol.name,
      kind: symbol_kind_to_string(symbol.kind),
      range: transform_range(symbol.range),
      selection_range: transform_range(symbol.selectionRange),
      detail: Map.get(symbol, :detail),
      children: Enum.map(Map.get(symbol, :children, []), &transform_symbol/1)
    }
  end
  
  defp transform_range(range) do
    %{
      start: %{
        line: range.start.line,
        character: range.start.character
      },
      end: %{
        line: range.end.line,
        character: range.end.character
      }
    }
  end
  
  defp transform_location(location) do
    %{
      uri: location.uri,
      file_path: uri_to_path(location.uri),
      range: transform_range(location.range)
    }
  end
  
  defp transform_diagnostic(diagnostic) do
    %{
      range: transform_range(diagnostic.range),
      severity: diagnostic_severity_to_string(diagnostic.severity),
      code: Map.get(diagnostic, :code),
      source: Map.get(diagnostic, :source),
      message: diagnostic.message,
      related_information: Enum.map(
        Map.get(diagnostic, :relatedInformation, []), 
        &transform_related_info/1
      )
    }
  end
  
  defp transform_related_info(info) do
    %{
      location: transform_location(info.location),
      message: info.message
    }
  end
  
  defp transform_workspace_edit(edit) do
    changes = Map.get(edit, :changes, %{})
    
    changes
    |> Enum.map(fn {uri, edits} -> 
      {uri_to_path(uri), Enum.map(edits, &transform_text_edit/1)}
    end)
    |> Map.new()
  end
  
  defp transform_text_edit(edit) do
    %{
      range: transform_range(edit.range),
      new_text: edit.newText
    }
  end
  
  defp uri_to_path(uri) do
    uri
    |> String.replace_prefix("file://", "")
    |> URI.decode()
  end
  
  defp maybe_filter_symbols(symbols, options) do
    include_declarations = Keyword.get(options, :include_declarations, true)
    include_definitions = Keyword.get(options, :include_definitions, true)
    include_implementations = Keyword.get(options, :include_implementations, false)
    
    symbols
    |> Enum.filter(fn symbol ->
      case symbol.kind do
        kind when kind in ["class", "interface", "enum"] ->
          include_declarations
        _ ->
          true
      end
    end)
  end
  
  # Convert LSP symbol kind to string representation
  defp symbol_kind_to_string(kind) when is_integer(kind) do
    case kind do
      1 -> "file"
      2 -> "module"
      3 -> "namespace"
      4 -> "package"
      5 -> "class"
      6 -> "method"
      7 -> "property"
      8 -> "field"
      9 -> "constructor"
      10 -> "enum"
      11 -> "interface"
      12 -> "function"
      13 -> "variable"
      14 -> "constant"
      15 -> "string"
      16 -> "number"
      17 -> "boolean"
      18 -> "array"
      19 -> "object"
      20 -> "key"
      21 -> "null"
      22 -> "enum_member"
      23 -> "struct"
      24 -> "event"
      25 -> "operator"
      26 -> "type_parameter"
      _ -> "unknown"
    end
  end
  
  defp symbol_kind_to_string(kind) when is_binary(kind), do: kind
  defp symbol_kind_to_string(_), do: "unknown"
  
  # Convert LSP diagnostic severity to string representation
  defp diagnostic_severity_to_string(severity) when is_integer(severity) do
    case severity do
      1 -> "error"
      2 -> "warning"
      3 -> "information"
      4 -> "hint"
      _ -> "unknown"
    end
  end
  
  defp diagnostic_severity_to_string(severity) when is_binary(severity), do: severity
  defp diagnostic_severity_to_string(_), do: "unknown"
end
