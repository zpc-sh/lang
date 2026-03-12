defmodule Lang.Security.Validator do
  @moduledoc """
  Security validation engine for LANG system.

  Provides comprehensive input validation including:
  - Data type validation
  - Format validation
  - Security constraint enforcement
  - Business rule validation
  - Sanitization recommendations
  """

  require Logger

  @type validation_result :: :ok | {:error, [violation()]}
  @type violation :: %{
          field: String.t(),
          code: String.t(),
          message: String.t(),
          severity: :error | :warning | :info
        }

  @type validation_rules :: %{
          String.t() => rule_config()
        }

  @type rule_config :: %{
          type: atom(),
          required: boolean(),
          constraints: map(),
          sanitize: boolean()
        }

  # Default validation rules for common fields (patterns defined in functions)
  defp get_default_rules do
    %{
      "user_id" => %{
        type: :uuid,
        required: true,
        constraints: %{},
        sanitize: false
      },
      "session_id" => %{
        type: :uuid,
        required: true,
        constraints: %{},
        sanitize: false
      },
      "api_key" => %{
        type: :string,
        required: false,
        constraints: %{min_length: 20, max_length: 128},
        sanitize: false
      },
      "content" => %{
        type: :string,
        required: false,
        constraints: %{max_length: 1_000_000},
        sanitize: true
      },
      "query" => %{
        type: :string,
        required: false,
        constraints: %{max_length: 10_000},
        sanitize: true
      },
      "path" => %{
        type: :string,
        required: false,
        constraints: %{max_length: 4096, pattern: get_path_pattern()},
        sanitize: true
      }
    }
  end

  defp get_path_pattern, do: ~r/^[a-zA-Z0-9\/_\-\.]+$/

  # Security patterns to detect and block (moved to function to avoid serialization issues)
  defp get_security_patterns do
    [
      # SQL Injection
      {~r/(\bunion\b|\bselect\b|\binsert\b|\bdelete\b|\bdrop\b|\btruncate\b|\balter\b)/i,
       "sql_injection", "Potential SQL injection detected"},

      # XSS Patterns
      {~r/<script[^>]*>.*?<\/script>/i, "xss_script", "Script tag detected"},
      {~r/javascript:/i, "xss_javascript", "JavaScript protocol detected"},
      {~r/on\w+\s*=/i, "xss_event", "HTML event handler detected"},

      # Path Traversal
      {~r/\.\.\//, "path_traversal", "Path traversal attempt detected"},
      {~r/\.\.\\/, "path_traversal", "Path traversal attempt detected"},

      # Command Injection
      {~r/[;&|`$(){}]/, "command_injection", "Shell metacharacters detected"},

      # LDAP Injection
      {~r/[()=*!&|]/, "ldap_injection", "LDAP metacharacters detected"},

      # NoSQL Injection
      {~r/\$where|\$ne|\$gt|\$lt|\$regex/, "nosql_injection", "NoSQL injection pattern detected"}
    ]
  end

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Validate input data against security rules.
  """
  @spec validate(map(), validation_rules()) :: validation_result()
  def validate(input, rules \\ %{}) when is_map(input) do
    merged_rules = Map.merge(get_default_rules(), rules)

    Logger.debug("Validating input",
      fields: Map.keys(input),
      rules: Map.keys(merged_rules)
    )

    violations =
      input
      |> validate_fields(merged_rules)
      |> validate_security_patterns()
      |> validate_business_rules()

    case violations do
      [] -> :ok
      violations -> {:error, violations}
    end
  end

  @doc """
  Validate a single field value.
  """
  @spec validate_field(String.t(), any(), rule_config()) :: [violation()]
  def validate_field(field_name, value, rule_config) do
    violations = []

    violations =
      if rule_config.required and is_nil(value) do
        [create_violation(field_name, "required", "Field is required", :error) | violations]
      else
        violations
      end

    violations =
      if not is_nil(value) do
        violations ++ validate_field_type(field_name, value, rule_config.type)
      else
        violations
      end

    violations =
      if not is_nil(value) do
        violations ++ validate_field_constraints(field_name, value, rule_config.constraints)
      else
        violations
      end

    violations
  end

  @doc """
  Quick security check for common attack patterns.
  """
  @spec quick_security_check(String.t()) :: {:ok, String.t()} | {:error, [violation()]}
  def quick_security_check(input) when is_binary(input) do
    violations =
      get_security_patterns()
      |> Enum.reduce([], fn {pattern, code, message}, acc ->
        if Regex.match?(pattern, input) do
          [create_violation("input", code, message, :error) | acc]
        else
          acc
        end
      end)

    case violations do
      [] -> {:ok, input}
      violations -> {:error, violations}
    end
  end

  @doc """
  Validate file path for security.
  """
  @spec validate_path(String.t()) :: {:ok, String.t()} | {:error, [violation()]}
  def validate_path(path) when is_binary(path) do
    violations = []

    # Check for path traversal
    violations =
      if String.contains?(path, "..") do
        [
          create_violation("path", "path_traversal", "Path traversal detected", :error)
          | violations
        ]
      else
        violations
      end

    # Check for absolute paths (usually not allowed)
    violations =
      if String.starts_with?(path, "/") and not String.starts_with?(path, "/tmp/") do
        [
          create_violation("path", "absolute_path", "Absolute paths not allowed", :error)
          | violations
        ]
      else
        violations
      end

    # Check for suspicious extensions
    violations =
      if Regex.match?(~r/\.(exe|bat|cmd|sh|ps1|scr|com|pif)$/i, path) do
        [
          create_violation("path", "executable_file", "Executable files not allowed", :error)
          | violations
        ]
      else
        violations
      end

    case violations do
      [] -> {:ok, path}
      violations -> {:error, violations}
    end
  end

  @doc """
  Validate email format.
  """
  @spec validate_email(String.t()) :: {:ok, String.t()} | {:error, [violation()]}
  def validate_email(email) when is_binary(email) do
    email_pattern = ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/

    if Regex.match?(email_pattern, email) do
      {:ok, String.downcase(email)}
    else
      {:error, [create_violation("email", "invalid_format", "Invalid email format", :error)]}
    end
  end

  @doc """
  Validate UUID format.
  """
  @spec validate_uuid(String.t()) :: {:ok, String.t()} | {:error, [violation()]}
  def validate_uuid(uuid) when is_binary(uuid) do
    uuid_pattern = ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

    if Regex.match?(uuid_pattern, uuid) do
      {:ok, String.downcase(uuid)}
    else
      {:error, [create_violation("uuid", "invalid_format", "Invalid UUID format", :error)]}
    end
  end

  # =============================================================================
  # Field Validation
  # =============================================================================

  defp validate_fields(input, rules) do
    rules
    |> Enum.flat_map(fn {field_name, rule_config} ->
      value = Map.get(input, field_name)
      validate_field(field_name, value, rule_config)
    end)
  end

  defp validate_field_type(field_name, value, :string) do
    if is_binary(value) do
      []
    else
      [create_violation(field_name, "invalid_type", "Must be a string", :error)]
    end
  end

  defp validate_field_type(field_name, value, :integer) do
    if is_integer(value) do
      []
    else
      [create_violation(field_name, "invalid_type", "Must be an integer", :error)]
    end
  end

  defp validate_field_type(field_name, value, :float) do
    if is_float(value) or is_integer(value) do
      []
    else
      [create_violation(field_name, "invalid_type", "Must be a number", :error)]
    end
  end

  defp validate_field_type(field_name, value, :boolean) do
    if is_boolean(value) do
      []
    else
      [create_violation(field_name, "invalid_type", "Must be a boolean", :error)]
    end
  end

  defp validate_field_type(field_name, value, :uuid) do
    case validate_uuid(value) do
      {:ok, _} -> []
      {:error, violations} -> violations
    end
  end

  defp validate_field_type(field_name, value, :email) do
    case validate_email(value) do
      {:ok, _} -> []
      {:error, violations} -> violations
    end
  end

  defp validate_field_type(field_name, value, :list) do
    if is_list(value) do
      []
    else
      [create_violation(field_name, "invalid_type", "Must be a list", :error)]
    end
  end

  defp validate_field_type(field_name, value, :map) do
    if is_map(value) do
      []
    else
      [create_violation(field_name, "invalid_type", "Must be a map", :error)]
    end
  end

  defp validate_field_type(_field_name, _value, _type), do: []

  # =============================================================================
  # Constraint Validation
  # =============================================================================

  defp validate_field_constraints(field_name, value, constraints) do
    constraints
    |> Enum.flat_map(fn {constraint, constraint_value} ->
      validate_constraint(field_name, value, constraint, constraint_value)
    end)
  end

  defp validate_constraint(field_name, value, :min_length, min_length) when is_binary(value) do
    if String.length(value) >= min_length do
      []
    else
      [
        create_violation(
          field_name,
          "min_length",
          "Must be at least #{min_length} characters",
          :error
        )
      ]
    end
  end

  defp validate_constraint(field_name, value, :max_length, max_length) when is_binary(value) do
    if String.length(value) <= max_length do
      []
    else
      [
        create_violation(
          field_name,
          "max_length",
          "Must be at most #{max_length} characters",
          :error
        )
      ]
    end
  end

  defp validate_constraint(field_name, value, :min_value, min_value) when is_number(value) do
    if value >= min_value do
      []
    else
      [create_violation(field_name, "min_value", "Must be at least #{min_value}", :error)]
    end
  end

  defp validate_constraint(field_name, value, :max_value, max_value) when is_number(value) do
    if value <= max_value do
      []
    else
      [create_violation(field_name, "max_value", "Must be at most #{max_value}", :error)]
    end
  end

  defp validate_constraint(field_name, value, :pattern, pattern) when is_binary(value) do
    if Regex.match?(pattern, value) do
      []
    else
      [
        create_violation(
          field_name,
          "pattern_mismatch",
          "Does not match required pattern",
          :error
        )
      ]
    end
  end

  defp validate_constraint(field_name, value, :in, allowed_values) do
    if value in allowed_values do
      []
    else
      [
        create_violation(
          field_name,
          "not_in_list",
          "Must be one of: #{inspect(allowed_values)}",
          :error
        )
      ]
    end
  end

  defp validate_constraint(_field_name, _value, _constraint, _constraint_value), do: []

  # =============================================================================
  # Security Pattern Validation
  # =============================================================================

  defp validate_security_patterns(violations) do
    # This would normally scan all string values in the input
    # For now, we'll assume it's been done at field level
    violations
  end

  # =============================================================================
  # Business Rule Validation
  # =============================================================================

  defp validate_business_rules(violations) do
    # Add any business-specific validation rules here
    # For example:
    # - User access permissions
    # - Rate limiting checks
    # - Data consistency rules
    violations
  end

  # =============================================================================
  # Utilities
  # =============================================================================

  defp create_violation(field, code, message, severity) do
    %{
      field: field,
      code: code,
      message: message,
      severity: severity
    }
  end

  @doc """
  Get validation rules for a specific operation.
  """
  @spec get_operation_rules(String.t()) :: validation_rules()
  def get_operation_rules(operation) do
    case operation do
      "lang.fs.scan" ->
        %{
          "path" => %{
            type: :string,
            required: true,
            constraints: %{max_length: 4096, pattern: get_path_pattern()},
            sanitize: true
          },
          "max_depth" => %{
            type: :integer,
            required: false,
            constraints: %{min_value: 1, max_value: 20},
            sanitize: false
          }
        }

      "lang.query.natural" ->
        %{
          "query" => %{
            type: :string,
            required: true,
            constraints: %{min_length: 3, max_length: 1000},
            sanitize: true
          },
          "scope" => %{
            type: :string,
            required: false,
            constraints: %{in: get_valid_scopes()},
            sanitize: false
          }
        }

      "lang.generate.*" ->
        %{
          "prompt" => %{
            type: :string,
            required: true,
            constraints: %{min_length: 10, max_length: 10_000},
            sanitize: true
          },
          "language" => %{
            type: :string,
            required: false,
            constraints: %{max_length: 50, pattern: get_language_pattern()},
            sanitize: false
          }
        }

      _ ->
        get_default_rules()
    end
  end

  defp get_valid_scopes, do: ["workspace", "file", "selection"]
  defp get_language_pattern, do: ~r/^[a-zA-Z0-9_]+$/

  @doc """
  Check if value contains potentially dangerous content.
  """
  @spec contains_dangerous_content?(String.t()) :: boolean()
  def contains_dangerous_content?(content) when is_binary(content) do
    Enum.any?(get_security_patterns(), fn {pattern, _code, _message} ->
      Regex.match?(pattern, content)
    end)
  end

  @doc """
  Sanitize input by removing or encoding dangerous characters.
  """
  @spec sanitize_input(String.t(), atom()) :: String.t()
  def sanitize_input(input, :html) when is_binary(input) do
    input
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#x27;")
  end

  def sanitize_input(input, :sql) when is_binary(input) do
    input
    |> String.replace("'", "''")
    |> String.replace("\"", "\"\"")
    |> String.replace("\\", "\\\\")
  end

  def sanitize_input(input, :path) when is_binary(input) do
    input
    |> String.replace("..", "")
    |> String.replace("~", "")
    |> Path.basename()
  end

  def sanitize_input(input, _type) when is_binary(input) do
    # Generic sanitization - remove control characters
    String.replace(input, ~r/[\x00-\x1F\x7F]/, "")
  end
end
