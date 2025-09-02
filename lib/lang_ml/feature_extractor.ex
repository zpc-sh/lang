defmodule Lang.ML.FeatureExtractor do
  @moduledoc """
  Feature extraction for MCP request analysis.

  Extracts numerical and categorical features from MCP requests for ML models.
  Features include:
  - Request size and complexity metrics
  - Tool usage patterns
  - Parameter structure analysis
  - Temporal patterns
  - Security-relevant indicators
  """

  @type feature_map :: %{
    request_size: non_neg_integer(),
    tool_count: non_neg_integer(),
    param_complexity: non_neg_integer(),
    nested_depth: non_neg_integer(),
    has_suspicious_patterns: boolean(),
    timestamp_hour: 0..23,
    method_complexity: float(),
    parameter_entropy: float(),
    tool_diversity: float(),
    request_frequency: float()
  }

  @doc """
  Create a new feature extractor instance.
  """
  @spec new() :: %{}
  def new do
    %{
      # Feature extraction state can be stored here
      known_methods: %{},
      method_counts: %{},
      user_patterns: %{}
    }
  end

  @doc """
  Extract features from an MCP request.

  Returns a map of numerical features suitable for ML models.
  """
  @spec extract_features(map(), map()) :: feature_map()
  def extract_features(_extractor, request) when is_map(request) do
    %{
      request_size: calculate_request_size(request),
      tool_count: count_tools(request),
      param_complexity: calculate_param_complexity(request),
      nested_depth: calculate_nested_depth(request),
      has_suspicious_patterns: detect_suspicious_patterns(request),
      timestamp_hour: DateTime.utc_now().hour,
      method_complexity: calculate_method_complexity(request),
      parameter_entropy: calculate_parameter_entropy(request),
      tool_diversity: calculate_tool_diversity(request),
      request_frequency: calculate_request_frequency(request)
    }
  end

  def extract_features(_extractor, _request) do
    # Return default features for invalid requests
    %{
      request_size: 0,
      tool_count: 0,
      param_complexity: 0,
      nested_depth: 0,
      has_suspicious_patterns: false,
      timestamp_hour: DateTime.utc_now().hour,
      method_complexity: 0.0,
      parameter_entropy: 0.0,
      tool_diversity: 0.0,
      request_frequency: 0.0
    }
  end

  # Private functions

  defp calculate_request_size(request) do
    try do
      Jason.encode!(request) |> byte_size()
    rescue
      _ -> 0
    end
  end

  defp count_tools(request) do
    case request do
      %{"params" => %{"tools" => tools}} when is_list(tools) -> length(tools)
      %{"tools" => tools} when is_list(tools) -> length(tools)
      _ -> 0
    end
  end

  defp calculate_param_complexity(request) do
    case request do
      %{"params" => params} when is_map(params) ->
        count_parameters_recursively(params)
      _ ->
        0
    end
  end

  defp count_parameters_recursively(data) when is_map(data) do
    Enum.reduce(data, map_size(data), fn {_key, value}, acc ->
      acc + count_parameters_recursively(value)
    end)
  end

  defp count_parameters_recursively(data) when is_list(data) do
    Enum.reduce(data, length(data), fn item, acc ->
      acc + count_parameters_recursively(item)
    end)
  end

  defp count_parameters_recursively(_data) do
    0
  end

  defp calculate_nested_depth(request) do
    case request do
      %{"params" => params} when is_map(params) ->
        calculate_depth_recursively(params, 0)
      _ ->
        0
    end
  end

  defp calculate_depth_recursively(data, current_depth) when is_map(data) do
    if map_size(data) == 0 do
      current_depth
    else
      max_child_depth = Enum.reduce(data, 0, fn {_key, value}, acc ->
        max(acc, calculate_depth_recursively(value, current_depth + 1))
      end)
      max(current_depth, max_child_depth)
    end
  end

  defp calculate_depth_recursively(data, current_depth) when is_list(data) do
    if data == [] do
      current_depth
    else
      max_child_depth = Enum.reduce(data, 0, fn item, acc ->
        max(acc, calculate_depth_recursively(item, current_depth + 1))
      end)
      max(current_depth, max_child_depth)
    end
  end

  defp calculate_depth_recursively(_data, current_depth) do
    current_depth
  end

  defp detect_suspicious_patterns(request) do
    suspicious_indicators = [
      # Check for SQL-like patterns
      fn req -> has_sql_patterns(req) end,
      # Check for script injection patterns
      fn req -> has_script_patterns(req) end,
      # Check for unusual parameter names
      fn req -> has_suspicious_param_names(req) end,
      # Check for oversized parameters
      fn req -> has_oversized_parameters(req) end,
      # Check for recursive structures
      fn req -> has_recursive_structures(req) end
    ]

    Enum.any?(suspicious_indicators, fn check -> check.(request) end)
  end

  defp has_sql_patterns(request) do
    str = inspect(request)
    sql_keywords = ["SELECT", "INSERT", "UPDATE", "DELETE", "DROP", "UNION", "EXEC"]
    Enum.any?(sql_keywords, &String.contains?(String.upcase(str), &1))
  end

  defp has_script_patterns(request) do
    str = inspect(request)
    script_patterns = ["<script", "javascript:", "onload=", "onerror="]
    Enum.any?(script_patterns, &String.contains?(String.downcase(str), &1))
  end

  defp has_suspicious_param_names(request) do
    case request do
      %{"params" => params} when is_map(params) ->
        param_names = extract_param_names(params)
        suspicious_names = ["password", "token", "secret", "key", "eval", "exec"]
        Enum.any?(param_names, fn name ->
          Enum.any?(suspicious_names, &String.contains?(String.downcase(name), &1))
        end)
      _ -> false
    end
  end

  defp extract_param_names(params) do
    extract_names_recursively(params, [])
  end

  defp extract_names_recursively(data, acc) when is_map(data) do
    Enum.reduce(data, acc, fn {key, value}, acc ->
      acc = [to_string(key) | acc]
      extract_names_recursively(value, acc)
    end)
  end

  defp extract_names_recursively(data, acc) when is_list(data) do
    Enum.reduce(data, acc, fn item, acc ->
      extract_names_recursively(item, acc)
    end)
  end

  defp extract_names_recursively(_data, acc) do
    acc
  end

  defp has_oversized_parameters(request) do
    case request do
      %{"params" => params} when is_map(params) ->
        Enum.any?(params, fn {_key, value} ->
          case value do
            str when is_binary(str) -> String.length(str) > 10000
            list when is_list(list) -> length(list) > 1000
            _ -> false
          end
        end)
      _ -> false
    end
  end

  defp has_recursive_structures(request) do
    # Simple check for excessive nesting
    calculate_nested_depth(request) > 10
  end

  defp calculate_method_complexity(request) do
    case request do
      %{"method" => method} when is_binary(method) ->
        # Calculate complexity based on method name
        method_length = String.length(method)
        dot_count = method |> String.graphemes() |> Enum.count(&(&1 == "."))
        (method_length + dot_count * 2) / 10.0
      _ ->
        0.0
    end
  end

  defp calculate_parameter_entropy(request) do
    case request do
      %{"params" => params} when is_map(params) ->
        param_names = extract_param_names(params)
        if param_names == [] do
          0.0
        else
          # Simple entropy calculation based on parameter name diversity
          unique_names = Enum.uniq(param_names)
          length(unique_names) / length(param_names)
        end
      _ ->
        0.0
    end
  end

  defp calculate_tool_diversity(request) do
    case request do
      %{"params" => %{"tools" => tools}} when is_list(tools) ->
        if tools == [] do
          0.0
        else
          tool_types = Enum.map(tools, fn
            %{"name" => name} when is_binary(name) ->
              name |> String.split(".") |> List.first()
            _ -> "unknown"
          end)

          unique_types = Enum.uniq(tool_types)
          length(unique_types) / length(tools)
        end
      _ ->
        0.0
    end
  end

  defp calculate_request_frequency(request) do
    # This would typically be calculated based on historical data
    # For now, return a simple heuristic based on request complexity
    complexity = calculate_param_complexity(request)
    tool_count = count_tools(request)

    # Higher complexity and tool count suggest higher frequency patterns
    min(1.0, (complexity + tool_count * 10) / 100.0)
  end
end