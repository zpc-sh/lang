defmodule Lang.Security.InputValidator do
  @moduledoc """
  Input validation and sanitization for LANG application.

  This module provides comprehensive validation for all user inputs to prevent
  security vulnerabilities like injection attacks, XSS, and DoS through oversized inputs.
  """

  require Logger
  alias Lang.Security.Secrets

  @doc """
  Validate content for text analysis.
  """
  def validate_content(content, format, options \\ %{}) do
    limits = Secrets.text_processing_limits()

    with :ok <- validate_content_size(content, limits.max_content_size),
         :ok <- validate_format(format),
         :ok <- validate_content_safety(content, format),
         :ok <- validate_parsing_safety(content, format),
         :ok <- validate_rate_limiting(options) do
      {:ok, sanitize_content(content, format)}
    end
  end

  @doc """
  Validate conversation rehearsal session data.
  """
  def validate_session_data(session_data) do
    limits = Secrets.text_processing_limits()

    with :ok <- validate_scenario_type(session_data.scenario),
         :ok <- validate_participants(session_data.participants),
         :ok <- validate_session_options(session_data.options, limits) do
      {:ok, sanitize_session_data(session_data)}
    end
  end

  @doc """
  Validate conversation turn data.
  """
  def validate_turn_data(turn_data) do
    with :ok <- validate_speaker(turn_data.speaker),
         :ok <- validate_message_content(turn_data.content),
         :ok <- validate_turn_metadata(turn_data.metadata || %{}) do
      {:ok, sanitize_turn_data(turn_data)}
    end
  end

  @doc """
  Validate time machine operations.
  """
  def validate_timeline_operation(operation, data) do
    limits = Secrets.text_processing_limits()

    case operation do
      :create_timeline -> validate_create_timeline(data, limits)
      :add_state -> validate_add_state(data, limits)
      :navigate -> validate_navigate_operation(data)
      :branch -> validate_branch_operation(data)
      _ -> {:error, :unknown_operation}
    end
  end

  @doc """
  Validate API authentication data.
  """
  def validate_auth_data(auth_data) do
    with :ok <- validate_api_key_format(auth_data.api_key),
         :ok <- validate_user_permissions(auth_data.permissions),
         :ok <- validate_session_context(auth_data.context || %{}) do
      {:ok, sanitize_auth_data(auth_data)}
    end
  end

  @doc """
  Validate LSP request data.
  """
  def validate_lsp_request(method, params) do
    with :ok <- validate_lsp_method(method),
         :ok <- validate_lsp_params(method, params),
         :ok <- validate_document_uri(params["textDocument"]["uri"] || "") do
      {:ok, sanitize_lsp_params(params)}
    end
  end

  @doc """
  Validate file upload data.
  """
  def validate_file_upload(file_data) do
    limits = Secrets.text_processing_limits()

    with :ok <- validate_file_size(file_data.size, limits.max_content_size),
         :ok <- validate_file_type(file_data.content_type),
         :ok <- validate_file_name(file_data.filename),
         :ok <- validate_file_content_safety(file_data.content) do
      {:ok, sanitize_file_data(file_data)}
    end
  end

  # Content validation functions

  defp validate_content_size(content, max_size) when is_binary(content) do
    size = byte_size(content)

    if size <= max_size do
      :ok
    else
      Logger.warning("Content too large", size: size, max_size: max_size)
      {:error, {:content_too_large, %{size: size, max_size: max_size}}}
    end
  end

  defp validate_content_size(content, max_size) do
    size = content |> inspect() |> byte_size()

    if size <= max_size do
      :ok
    else
      Logger.warning("Content too large", size: size, max_size: max_size)
      {:error, {:content_too_large, %{size: size, max_size: max_size}}}
    end
  end

  defp validate_format(format) do
    allowed_formats = [
      "text",
      "markdown",
      "javascript",
      "python",
      "elixir",
      "rust",
      "go",
      "json",
      "yaml",
      "toml",
      "xml",
      "csv",
      "sql",
      "conversation",
      "email",
      "log"
    ]

    if format in allowed_formats do
      :ok
    else
      Logger.warning("Unsupported format", format: format)
      {:error, {:unsupported_format, format}}
    end
  end

  defp validate_content_safety(content, format) when is_binary(content) do
    # Check for potentially malicious patterns
    malicious_patterns = get_malicious_patterns(format)

    case Enum.find(malicious_patterns, fn {_name, pattern} -> Regex.match?(pattern, content) end) do
      nil ->
        :ok

      {pattern_name, _pattern} ->
        Logger.warning("Potentially malicious content detected",
          pattern: pattern_name,
          format: format
        )

        {:error, {:malicious_content_detected, pattern_name}}
    end
  end

  defp validate_content_safety(_content, _format), do: :ok

  defp validate_parsing_safety(content, format) when is_binary(content) do
    case format do
      "json" -> validate_json_safety(content)
      "yaml" -> validate_yaml_safety(content)
      "xml" -> validate_xml_safety(content)
      _ -> :ok
    end
  end

  defp validate_parsing_safety(_content, _format), do: :ok

  defp validate_rate_limiting(options) do
    # Check if rate limiting should be bypassed (for internal operations)
    if Map.get(options, :bypass_rate_limit, false) do
      :ok
    else
      # Rate limiting will be checked by the middleware
      :ok
    end
  end

  # JSON-specific validation
  defp validate_json_safety(content) do
    nesting_level = count_json_nesting(content)

    if nesting_level > 50 do
      Logger.warning("JSON too deeply nested", nesting_level: nesting_level)
      {:error, {:json_too_deeply_nested, nesting_level}}
    else
      :ok
    end
  end

  defp count_json_nesting(content) do
    # Simple nesting counter - counts maximum consecutive opening braces/brackets
    content
    |> String.graphemes()
    |> Enum.reduce({0, 0}, fn char, {current_depth, max_depth} ->
      case char do
        "{" -> {current_depth + 1, max(current_depth + 1, max_depth)}
        "[" -> {current_depth + 1, max(current_depth + 1, max_depth)}
        "}" -> {max(current_depth - 1, 0), max_depth}
        "]" -> {max(current_depth - 1, 0), max_depth}
        _ -> {current_depth, max_depth}
      end
    end)
    |> elem(1)
  end

  # YAML-specific validation  
  defp validate_yaml_safety(content) do
    dangerous_patterns = [
      # Anchors
      ~r/&\w+/,
      # References  
      ~r/\*\w+/,
      # Merge keys
      ~r/<<:/,
      # Python objects
      ~r/!!python/,
      # Java objects
      ~r/!!java/
    ]

    if Enum.any?(dangerous_patterns, &Regex.match?(&1, content)) do
      Logger.warning("Potentially dangerous YAML constructs detected")
      {:error, :dangerous_yaml_constructs}
    else
      :ok
    end
  end

  # XML-specific validation
  defp validate_xml_safety(content) do
    dangerous_patterns = [
      # Entity declarations
      ~r/<!ENTITY/i,
      # External DTD
      ~r/<!DOCTYPE.*SYSTEM/i,
      # DTD elements
      ~r/<!ELEMENT/i
    ]

    if Enum.any?(dangerous_patterns, &Regex.match?(&1, content)) do
      Logger.warning("Potentially dangerous XML constructs detected")
      {:error, :dangerous_xml_constructs}
    else
      :ok
    end
  end

  # Session validation functions
  defp validate_scenario_type(scenario) when is_binary(scenario) do
    allowed_scenarios = [
      "job_interview",
      "sales_call",
      "customer_support",
      "negotiation",
      "presentation",
      "performance_review",
      "conflict_resolution",
      "training_session",
      "consultation",
      "brainstorming"
    ]

    if scenario in allowed_scenarios do
      :ok
    else
      Logger.warning("Unknown scenario type", scenario: scenario)
      {:error, {:unknown_scenario, scenario}}
    end
  end

  defp validate_scenario_type(_), do: {:error, :invalid_scenario_type}

  defp validate_participants(participants) when is_list(participants) do
    if length(participants) >= 2 and length(participants) <= 10 do
      if Enum.all?(participants, &validate_participant_name/1) do
        :ok
      else
        {:error, :invalid_participant_names}
      end
    else
      {:error, :invalid_participant_count}
    end
  end

  defp validate_participants(_), do: {:error, :invalid_participants_format}

  defp validate_participant_name(name) when is_binary(name) do
    String.match?(name, ~r/^[a-zA-Z0-9_\s-]{1,50}$/)
  end

  defp validate_participant_name(_), do: false

  defp validate_session_options(options, limits) when is_map(options) do
    max_turns = Map.get(options, :max_turns, limits.max_conversation_turns)

    if max_turns > 0 and max_turns <= limits.max_conversation_turns do
      :ok
    else
      {:error, {:invalid_max_turns, max_turns}}
    end
  end

  defp validate_session_options(_, _), do: {:error, :invalid_options_format}

  # Turn validation functions
  defp validate_speaker(speaker) when is_binary(speaker) do
    if String.match?(speaker, ~r/^[a-zA-Z0-9_\s-]{1,50}$/) do
      :ok
    else
      {:error, :invalid_speaker_name}
    end
  end

  defp validate_speaker(_), do: {:error, :invalid_speaker_format}

  defp validate_message_content(content) when is_binary(content) do
    if String.length(content) > 0 and String.length(content) <= 10_000 do
      :ok
    else
      {:error, :invalid_message_length}
    end
  end

  defp validate_message_content(_), do: {:error, :invalid_message_format}

  defp validate_turn_metadata(metadata) when is_map(metadata) do
    # Validate metadata keys and values
    if map_size(metadata) <= 20 do
      :ok
    else
      {:error, :too_many_metadata_fields}
    end
  end

  defp validate_turn_metadata(_), do: {:error, :invalid_metadata_format}

  # Timeline operation validation
  defp validate_create_timeline(data, limits) do
    with :ok <- validate_content_size(data.initial_state, limits.max_content_size),
         :ok <- validate_timeline_metadata(data.metadata || %{}) do
      :ok
    end
  end

  defp validate_add_state(data, limits) do
    with :ok <- validate_content_size(data.state_data, limits.max_content_size),
         :ok <- validate_transition_metadata(data.metadata || %{}) do
      :ok
    end
  end

  defp validate_navigate_operation(data) do
    if is_binary(data.timeline_id) and is_binary(data.state_id) do
      :ok
    else
      {:error, :invalid_navigation_parameters}
    end
  end

  defp validate_branch_operation(data) do
    if is_binary(data.timeline_id) and is_binary(data.branch_point_id) do
      :ok
    else
      {:error, :invalid_branch_parameters}
    end
  end

  defp validate_timeline_metadata(metadata) when is_map(metadata) do
    if map_size(metadata) <= 50 do
      :ok
    else
      {:error, :too_many_metadata_fields}
    end
  end

  defp validate_timeline_metadata(_), do: {:error, :invalid_metadata_format}

  defp validate_transition_metadata(metadata) when is_map(metadata) do
    if map_size(metadata) <= 20 do
      :ok
    else
      {:error, :too_many_metadata_fields}
    end
  end

  defp validate_transition_metadata(_), do: {:error, :invalid_metadata_format}

  # Authentication validation
  defp validate_api_key_format(api_key) when is_binary(api_key) do
    if String.match?(api_key, ~r/^[a-zA-Z0-9_-]{32,128}$/) do
      :ok
    else
      {:error, :invalid_api_key_format}
    end
  end

  defp validate_api_key_format(_), do: {:error, :invalid_api_key_format}

  defp validate_user_permissions(permissions) when is_map(permissions) do
    required_fields = [:read, :write, :admin]

    if Enum.all?(required_fields, fn field -> Map.has_key?(permissions, field) end) do
      :ok
    else
      {:error, :missing_permission_fields}
    end
  end

  defp validate_user_permissions(_), do: {:error, :invalid_permissions_format}

  defp validate_session_context(context) when is_map(context) do
    if map_size(context) <= 10 do
      :ok
    else
      {:error, :too_many_context_fields}
    end
  end

  defp validate_session_context(_), do: {:error, :invalid_context_format}

  # LSP validation
  defp validate_lsp_method(method) when is_binary(method) do
    allowed_methods = [
      "initialize",
      "initialized",
      "shutdown",
      "exit",
      "textDocument/didOpen",
      "textDocument/didChange",
      "textDocument/didClose",
      "textDocument/completion",
      "textDocument/hover",
      "textDocument/diagnostics",
      "workspace/executeCommand"
    ]

    if method in allowed_methods do
      :ok
    else
      {:error, {:unknown_lsp_method, method}}
    end
  end

  defp validate_lsp_method(_), do: {:error, :invalid_lsp_method_format}

  defp validate_lsp_params(method, params) when is_map(params) do
    case method do
      "textDocument/" <> _ -> validate_text_document_params(params)
      "workspace/" <> _ -> validate_workspace_params(params)
      _ -> :ok
    end
  end

  defp validate_lsp_params(_, _), do: {:error, :invalid_lsp_params_format}

  defp validate_text_document_params(params) do
    case params do
      %{"textDocument" => %{"uri" => uri}} when is_binary(uri) -> :ok
      _ -> {:error, :missing_text_document_uri}
    end
  end

  defp validate_workspace_params(_params), do: :ok

  defp validate_document_uri(uri) when is_binary(uri) do
    if String.match?(uri, ~r/^(file|conversation):\/\/.+/) do
      :ok
    else
      {:error, :invalid_document_uri}
    end
  end

  defp validate_document_uri(_), do: {:error, :invalid_document_uri_format}

  # File validation
  defp validate_file_size(size, max_size) when is_integer(size) do
    if size > 0 and size <= max_size do
      :ok
    else
      {:error, {:invalid_file_size, size, max_size}}
    end
  end

  defp validate_file_size(_, _), do: {:error, :invalid_file_size_format}

  defp validate_file_type(content_type) when is_binary(content_type) do
    allowed_types = [
      "text/plain",
      "text/markdown",
      "text/html",
      "application/json",
      "application/yaml",
      "text/yaml",
      "application/xml",
      "text/xml",
      "text/javascript",
      "application/javascript",
      "text/x-python",
      "text/x-elixir",
      "text/x-rust"
    ]

    if content_type in allowed_types do
      :ok
    else
      {:error, {:unsupported_file_type, content_type}}
    end
  end

  defp validate_file_type(_), do: {:error, :invalid_content_type_format}

  defp validate_file_name(filename) when is_binary(filename) do
    if String.match?(filename, ~r/^[a-zA-Z0-9._-]+\.[a-zA-Z0-9]+$/) and
         String.length(filename) <= 255 do
      :ok
    else
      {:error, :invalid_filename}
    end
  end

  defp validate_file_name(_), do: {:error, :invalid_filename_format}

  defp validate_file_content_safety(content) do
    validate_content_safety(content, "text")
  end

  # Sanitization functions
  defp sanitize_content(content, _format) when is_binary(content) do
    content
    |> String.trim()
    |> remove_null_bytes()
  end

  defp sanitize_content(content, _format), do: content

  defp sanitize_session_data(session_data) do
    %{
      session_data
      | scenario: String.trim(session_data.scenario),
        participants: Enum.map(session_data.participants, &String.trim/1)
    }
  end

  defp sanitize_turn_data(turn_data) do
    %{
      turn_data
      | speaker: String.trim(turn_data.speaker),
        content: String.trim(turn_data.content)
    }
  end

  defp sanitize_auth_data(auth_data) do
    %{auth_data | api_key: String.trim(auth_data.api_key)}
  end

  defp sanitize_lsp_params(params), do: params

  defp sanitize_file_data(file_data) do
    %{
      file_data
      | filename: String.trim(file_data.filename),
        content_type: String.trim(file_data.content_type)
    }
  end

  defp remove_null_bytes(content) do
    String.replace(content, <<0>>, "")
  end

  defp get_malicious_patterns(format) do
    base_patterns = [
      {"script_tag", ~r/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/mi},
      {"javascript_url", ~r/javascript:/i},
      {"data_url", ~r/data:[^;]*;base64/i},
      {"sql_injection", ~r/(union|select|insert|update|delete|drop|create|alter)\s+/i}
    ]

    format_specific =
      case format do
        "html" ->
          [
            {"iframe_tag", ~r/<iframe\b[^>]*>/i},
            {"object_tag", ~r/<object\b[^>]*>/i},
            {"embed_tag", ~r/<embed\b[^>]*>/i}
          ]

        "javascript" ->
          [
            {"eval_usage", ~r/eval\s*\(/i},
            {"function_constructor", ~r/new\s+Function\s*\(/i}
          ]

        _ ->
          []
      end

    base_patterns ++ format_specific
  end
end
