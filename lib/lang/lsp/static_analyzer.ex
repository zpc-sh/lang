defmodule Lang.LSP.StaticAnalyzer do
  @moduledoc """
  Static analysis for LSP codebase security and quality.
  
  Provides:
  - Security vulnerability detection
  - Code quality analysis  
  - Architecture compliance checking
  - Performance bottleneck identification
  - Race condition detection patterns
  """
  
  require Logger
  
  alias Lang.Native.TreeParser
  
  @type analysis_result :: %{
    security_issues: [security_issue()],
    quality_issues: [quality_issue()], 
    performance_issues: [performance_issue()],
    architecture_violations: [architecture_violation()]
  }
  
  @type security_issue :: %{
    type: atom(),
    severity: :critical | :high | :medium | :low,
    file: String.t(),
    line: non_neg_integer(),
    message: String.t(),
    suggestion: String.t()
  }
  
  @type quality_issue :: %{
    type: atom(),
    severity: :error | :warning | :info,
    file: String.t(),
    line: non_neg_integer(), 
    message: String.t()
  }
  
  @type performance_issue :: %{
    type: atom(),
    severity: :critical | :high | :medium | :low,
    file: String.t(),
    line: non_neg_integer(),
    message: String.t(),
    impact: String.t()
  }
  
  @type architecture_violation :: %{
    type: atom(),
    file: String.t(),
    line: non_neg_integer(),
    message: String.t(),
    expected: String.t(),
    actual: String.t()
  }
  
  # Security patterns to detect (runtime to avoid non-literal attribute issues)
  defp security_patterns do
    [
    # SQL injection risks
    {~r/Repo\.(query|query!)\([^,]*\$\{/, :sql_injection, :critical, 
     "Potential SQL injection via string interpolation"},
    
    # Path traversal risks
    {~r/File\.(read|write|open).*\.\.\//i, :path_traversal, :high,
     "Potential path traversal vulnerability"},
    
    # Command injection risks  
    {~r/(System\.cmd|:os\.cmd|Port\.open).*\$\{/, :command_injection, :critical,
     "Potential command injection via string interpolation"},
    
    # Unsafe deserialization
    {~r/:erlang\.binary_to_term\([^,]*safe: false/, :unsafe_deserialization, :high,
     "Unsafe binary deserialization"},
     
    # Hardcoded secrets
    {~r/(password|secret|key|token)\s*=\s*["|'][^"|']{8,}["|']/, :hardcoded_secret, :critical,
     "Potential hardcoded secret"},
     
    # Unsafe random number generation
    {~r/:rand\.uniform|:random\.uniform/, :weak_random, :medium,
     "Use :crypto.strong_rand_bytes for cryptographic operations"}
    ]
  end
  
  # Performance anti-patterns (runtime to avoid non-literal attribute issues)
  defp performance_patterns do
    [
    # Unbounded operations
    {~r/Enum\.(map|filter|reduce).*Repo\./, :n_plus_one, :high,
     "Potential N+1 query problem"},
     
    # Blocking operations in GenServer  
    {~r/handle_(call|cast|info).*Process\.sleep/, :blocking_genserver, :medium,
     "Blocking operation in GenServer callback"},
     
    # Memory leaks
    {~r/Agent\.start.*name:/, :unnamed_agent, :low,
     "Consider using named agent to prevent leaks"},
     
    # Inefficient string operations
    {~r/String\.split.*\|>\s*Enum\.join/, :inefficient_string_ops, :low,
     "Consider using String.replace for simple substitutions"}
    ]
  end
  
  # Architecture patterns (runtime to avoid non-literal attribute issues)
  defp architecture_patterns do
    [
    # Direct database access from controllers
    {~r/Controller.*Repo\.(get|all|insert|update|delete)/, :controller_db_access,
     "Controllers should use contexts, not direct Repo access"},
     
    # Business logic in views
    {~r/View.*def.*\s+case\s+/, :business_logic_in_view,
     "Views should only handle presentation logic"},
     
    # Missing supervision
    {~r/GenServer\.start_link.*name:.*\[\]/, :missing_supervision,
     "GenServers should be started under supervision tree"}
    ]
  end
  
  @doc """
  Analyzes LSP codebase for security, quality, and architecture issues.
  """
  @spec analyze_codebase(String.t()) :: {:ok, analysis_result()} | {:error, String.t()}
  def analyze_codebase(root_path) do
    with {:ok, files} <- get_elixir_files(root_path) do
      analysis = %{
        security_issues: [],
        quality_issues: [],
        performance_issues: [],
        architecture_violations: []
      }
      
      result = Enum.reduce(files, analysis, fn file, acc ->
        case analyze_file(file) do
          {:ok, file_analysis} -> merge_analysis(acc, file_analysis)
          {:error, _reason} -> acc
        end
      end)
      
      {:ok, result}
    end
  end
  
  @doc """
  Analyzes a single file for issues.
  """
  @spec analyze_file(String.t()) :: {:ok, analysis_result()} | {:error, String.t()}
  def analyze_file(file_path) do
    with {:ok, content} <- File.read(file_path) do
      analysis = %{
        security_issues: analyze_security_issues(file_path, content),
        quality_issues: analyze_quality_issues(file_path, content),
        performance_issues: analyze_performance_issues(file_path, content),
        architecture_violations: analyze_architecture_violations(file_path, content)
      }
      
      {:ok, analysis}
    end
  end
  
  @doc """
  Analyzes LSP server for runtime security issues.
  """
  @spec analyze_lsp_server_security() :: analysis_result()
  def analyze_lsp_server_security do
    server_files = [
      "lib/lang/lsp/server.ex",
      "lib/lang/lsp/dispatch.ex", 
      "lib/lang/mcp/stream_bridge.ex",
      "lib/lang/lsp/security_validator.ex"
    ]
    
    Enum.reduce(server_files, %{security_issues: [], quality_issues: [], 
                                performance_issues: [], architecture_violations: []}, 
    fn file, acc ->
      case analyze_file(file) do
        {:ok, analysis} -> merge_analysis(acc, analysis)
        {:error, _} -> acc
      end
    end)
  end
  
  @doc """
  Detects race condition patterns in multi-client code.
  """
  @spec detect_race_conditions(String.t()) :: [security_issue()]
  def detect_race_conditions(content) do
    race_patterns = [
      # Shared state without synchronization
      {~r/Map\.(put|update).*state\..*clients/, :unsynchronized_shared_state,
       "Potential race condition in shared client state"},
       
      # Message handling without ordering
      {~r/handle_info.*spawn/, :unordered_message_processing, 
       "Spawned processes may create message ordering issues"},
       
      # Document state races
      {~r/documents.*Map\.(put|update)/, :document_state_race,
       "Document state modifications may race between clients"}
    ]
    
    lines = String.split(content, "\n")
    
    Enum.flat_map(lines, fn {line, line_num} ->
      Enum.flat_map(race_patterns, fn {pattern, type, message} ->
        if Regex.match?(pattern, line) do
          [%{
            type: type,
            severity: :medium,
            file: "analyzed_content",
            line: line_num + 1,
            message: message,
            suggestion: get_race_condition_suggestion(type)
          }]
        else
          []
        end
      end)
    end)
    |> Enum.with_index()
    |> Enum.map(fn {issue, _} -> issue end)
  end
  
  @doc """
  Generates security report for LSP architecture.
  """
  @spec generate_security_report(String.t()) :: String.t()
  def generate_security_report(root_path) do
    case analyze_codebase(root_path) do
      {:ok, analysis} -> format_security_report(analysis)
      {:error, reason} -> "Analysis failed: #{reason}"
    end
  end
  
  # Private functions
  
  defp get_elixir_files(root_path) do
    case File.ls(root_path) do
      {:ok, _} ->
        files = Path.wildcard(Path.join([root_path, "**", "*.ex"]))
        {:ok, files}
      {:error, reason} ->
        {:error, "Cannot read directory: #{reason}"}
    end
  end
  
  defp analyze_security_issues(file_path, content) do
    lines = String.split(content, "\n")
    
    Enum.flat_map(security_patterns(), fn {pattern, type, severity, message} ->
      find_pattern_matches(lines, pattern, %{
        type: type,
        severity: severity,
        file: file_path,
        message: message,
        suggestion: get_security_suggestion(type)
      })
    end)
  end
  
  defp analyze_quality_issues(file_path, content) do
    issues = []
    
    # Check for TODO/FIXME/HACK comments
    todos = find_todo_comments(content, file_path)
    
    # Check for overly complex functions
    complex_functions = find_complex_functions(content, file_path)
    
    # Check for code smells
    code_smells = find_code_smells(content, file_path)
    
    issues ++ todos ++ complex_functions ++ code_smells
  end
  
  defp analyze_performance_issues(file_path, content) do
    lines = String.split(content, "\n")
    
    Enum.flat_map(performance_patterns(), fn {pattern, type, severity, message} ->
      find_pattern_matches(lines, pattern, %{
        type: type,
        severity: severity,
        file: file_path,
        message: message,
        impact: get_performance_impact(type)
      })
    end)
  end
  
  defp analyze_architecture_violations(file_path, content) do
    lines = String.split(content, "\n")
    
    Enum.flat_map(architecture_patterns(), fn {pattern, type, message} ->
      matches = find_pattern_matches(lines, pattern, %{
        type: type,
        file: file_path,
        message: message
      })
      
      Enum.map(matches, fn match ->
        Map.merge(match, %{
          expected: get_expected_pattern(type),
          actual: "See file for details"
        })
      end)
    end)
  end
  
  defp find_pattern_matches(lines, pattern, base_issue) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, line_num} ->
      if Regex.match?(pattern, line) do
        [Map.put(base_issue, :line, line_num + 1)]
      else
        []
      end
    end)
  end
  
  defp find_todo_comments(content, file_path) do
    lines = String.split(content, "\n")
    todo_pattern = ~r/#\s*(TODO|FIXME|HACK|XXX):?\s*(.+)/i
    
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, line_num} ->
      case Regex.run(todo_pattern, line) do
        [_full, type, comment] ->
          severity = case String.upcase(type) do
            "FIXME" -> :error
            "HACK" -> :warning
            _ -> :info
          end
          
          [%{
            type: :todo_comment,
            severity: severity,
            file: file_path,
            line: line_num + 1,
            message: "#{type}: #{comment}"
          }]
        
        nil -> []
      end
    end)
  end
  
  defp find_complex_functions(content, file_path) do
    # Simple complexity metric: count if/case/cond statements
    lines = String.split(content, "\n")
    
    lines
    |> Enum.with_index()
    |> Enum.reduce({[], nil, 0}, fn {line, line_num}, {issues, current_func, complexity} ->
      cond do
        # Function definition
        Regex.match?(~r/^\s*def\s+/, line) ->
          new_issues = if complexity > 10 and current_func do
            [%{
              type: :high_complexity,
              severity: :warning,
              file: file_path,
              line: elem(current_func, 1),
              message: "Function #{elem(current_func, 0)} has high complexity (#{complexity})"
            } | issues]
          else
            issues
          end
          
          func_name = extract_function_name(line)
          {new_issues, {func_name, line_num + 1}, 0}
        
        # Complexity indicators
        Regex.match?(~r/\b(if|case|cond|unless|with)\b/, line) ->
          {issues, current_func, complexity + 1}
        
        true ->
          {issues, current_func, complexity}
      end
    end)
    |> elem(0)
  end
  
  defp find_code_smells(content, file_path) do
    smells = []
    
    # Long parameter lists
    long_params = find_long_parameter_lists(content, file_path)
    
    # Deeply nested code
    deep_nesting = find_deep_nesting(content, file_path)
    
    smells ++ long_params ++ deep_nesting
  end
  
  defp find_long_parameter_lists(content, file_path) do
    lines = String.split(content, "\n")
    
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, line_num} ->
      if Regex.match?(~r/def\s+\w+\([^)]{50,}\)/, line) do
        [%{
          type: :long_parameter_list,
          severity: :warning,
          file: file_path,
          line: line_num + 1,
          message: "Function has long parameter list - consider using a struct"
        }]
      else
        []
      end
    end)
  end
  
  defp find_deep_nesting(content, file_path) do
    lines = String.split(content, "\n")
    
    lines
    |> Enum.with_index()
    |> Enum.reduce({[], 0}, fn {line, line_num}, {issues, nesting} ->
      # Simple nesting detection based on indentation
      indent = String.length(line) - String.length(String.trim_leading(line))
      new_nesting = div(indent, 2)  # Assume 2-space indentation
      
      new_issues = if new_nesting > 6 do
        [%{
          type: :deep_nesting,
          severity: :warning,
          file: file_path,
          line: line_num + 1,
          message: "Code is deeply nested (#{new_nesting} levels) - consider extracting functions"
        } | issues]
      else
        issues
      end
      
      {new_issues, new_nesting}
    end)
    |> elem(0)
  end
  
  defp merge_analysis(acc, new_analysis) do
    %{
      security_issues: acc.security_issues ++ new_analysis.security_issues,
      quality_issues: acc.quality_issues ++ new_analysis.quality_issues,
      performance_issues: acc.performance_issues ++ new_analysis.performance_issues,
      architecture_violations: acc.architecture_violations ++ new_analysis.architecture_violations
    }
  end
  
  defp extract_function_name(line) do
    case Regex.run(~r/def\s+([a-zA-Z_][a-zA-Z0-9_!?]*)/u, line) do
      [_full, name] -> name
      nil -> "unknown"
    end
  end
  
  defp get_security_suggestion(:sql_injection), do: "Use parameterized queries with Ecto.Query"
  defp get_security_suggestion(:path_traversal), do: "Validate and sanitize file paths"
  defp get_security_suggestion(:command_injection), do: "Use safe command execution with explicit arguments"
  defp get_security_suggestion(:unsafe_deserialization), do: "Use safe: :true option or validate input"
  defp get_security_suggestion(:hardcoded_secret), do: "Use environment variables or secure configuration"
  defp get_security_suggestion(:weak_random), do: "Use :crypto.strong_rand_bytes/1"
  defp get_security_suggestion(_), do: "Review security implications"
  
  defp get_performance_impact(:n_plus_one), do: "Can cause significant database load under scale"
  defp get_performance_impact(:blocking_genserver), do: "Can block message processing"
  defp get_performance_impact(:unnamed_agent), do: "May cause memory leaks over time"
  defp get_performance_impact(:inefficient_string_ops), do: "Minor performance impact"
  defp get_performance_impact(_), do: "Potential performance degradation"
  
  defp get_expected_pattern(:controller_db_access), do: "Use Phoenix contexts for data access"
  defp get_expected_pattern(:business_logic_in_view), do: "Move logic to contexts or controllers"
  defp get_expected_pattern(:missing_supervision), do: "Start GenServers under supervision tree"
  defp get_expected_pattern(_), do: "Follow Phoenix architectural patterns"
  
  defp get_race_condition_suggestion(:unsynchronized_shared_state), 
    do: "Use GenServer for synchronized state access"
  defp get_race_condition_suggestion(:unordered_message_processing),
    do: "Consider using Task.Supervisor or ordered message processing"
  defp get_race_condition_suggestion(:document_state_race),
    do: "Implement document versioning or locking mechanism"
  defp get_race_condition_suggestion(_), do: "Review for thread safety"
  
  defp format_security_report(analysis) do
    """
    # LSP Security Analysis Report
    
    Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    
    ## Summary
    - Security Issues: #{length(analysis.security_issues)}
    - Quality Issues: #{length(analysis.quality_issues)}
    - Performance Issues: #{length(analysis.performance_issues)}
    - Architecture Violations: #{length(analysis.architecture_violations)}
    
    ## Critical Security Issues
    #{format_issues(analysis.security_issues, :critical)}
    
    ## High Priority Security Issues  
    #{format_issues(analysis.security_issues, :high)}
    
    ## Performance Issues
    #{format_performance_issues(analysis.performance_issues)}
    
    ## Architecture Violations
    #{format_architecture_violations(analysis.architecture_violations)}
    
    ## Recommendations
    1. Address all critical security issues immediately
    2. Implement comprehensive input validation
    3. Add rate limiting and resource exhaustion protection
    4. Review multi-client race condition patterns
    5. Add comprehensive security testing
    """
  end
  
  defp format_issues(issues, severity) do
    filtered = Enum.filter(issues, &(&1.severity == severity))
    
    if Enum.empty?(filtered) do
      "None found.\n"
    else
      Enum.map(filtered, fn issue ->
        "- **#{issue.file}:#{issue.line}** - #{issue.message}"
      end)
      |> Enum.join("\n")
    end
  end
  
  defp format_performance_issues(issues) do
    if Enum.empty?(issues) do
      "None found.\n"
    else
      Enum.map(issues, fn issue ->
        "- **#{issue.file}:#{issue.line}** - #{issue.message} (Impact: #{issue.impact})"
      end)
      |> Enum.join("\n")
    end
  end
  
  defp format_architecture_violations(violations) do
    if Enum.empty?(violations) do
      "None found.\n"
    else
      Enum.map(violations, fn violation ->
        "- **#{violation.file}:#{violation.line}** - #{violation.message}\n  Expected: #{violation.expected}"
      end)
      |> Enum.join("\n")
    end
  end
end
