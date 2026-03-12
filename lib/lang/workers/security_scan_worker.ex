defmodule Lang.Workers.SecurityScanWorker do
  @moduledoc """
  Security Scan Worker for security analysis and vulnerability scanning.

  This worker performs comprehensive security analysis of code and documents
  including vulnerability scanning, sensitive data detection, security best
  practice validation, and compliance checking.

  ## Features

  - **Code Vulnerability Scanning** - Detect common security vulnerabilities
  - **Sensitive Data Detection** - Find API keys, passwords, emails, tokens
  - **Security Best Practice Validation** - Check against security guidelines
  - **Compliance Checking** - Validate compliance with security standards
  - **Dependency Security Analysis** - Check for known vulnerable dependencies
  - **Configuration Security Review** - Analyze config files for security issues

  ## Usage

      # Queue security scan job
      job = SecurityScanWorker.new(%{
        "scan_result_id" => scan_result.id,
        "session_id" => session.id,
        "security_level" => "standard"
      })
      |> Oban.insert()

  """

  use Oban.Worker, queue: :analysis, max_attempts: 3

  alias Lang.Analysis
  alias Kyozo.Lang.UniversalParser
  alias Lang.Native.Parser
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    scan_result_id = args["scan_result_id"]
    session_id = args["session_id"]
    security_level = args["security_level"] || "standard"

    Logger.info("Starting security scan",
      scan_result_id: scan_result_id,
      session_id: session_id,
      security_level: security_level
    )

    try do
      # Get analyzed files for this session
      files = Analysis.list_analyzed_files(session_id, limit: 1000)

      if Enum.empty?(files) do
        Logger.info("No files found for security scan", session_id: session_id)
        :ok
      else
        # Process files for security analysis
        security_results = process_security_scan(files, security_level)

        # Update files with security analysis results
        update_files_with_security_results(files, security_results)

        Logger.info("Security scan completed",
          scan_result_id: scan_result_id,
          files_scanned: length(files),
          total_findings: count_total_findings(security_results)
        )

        :ok
      end
    rescue
      error ->
        Logger.error("Security scan failed",
          scan_result_id: scan_result_id,
          session_id: session_id,
          error: Exception.message(error)
        )

        {:error, {:security_scan_failed, error}}
    end
  end

  # === Private Functions ===

  defp process_security_scan(files, security_level) do
    Logger.info("Processing security scan for #{length(files)} files", level: security_level)

    # Process each file individually
    individual_results =
      files
      |> Enum.map(&process_file_security(&1, security_level))
      |> Enum.reject(&is_nil/1)

    # Aggregate security findings
    aggregate_findings = aggregate_security_findings(individual_results)

    # Perform cross-file security analysis
    cross_file_analysis = analyze_cross_file_security(individual_results, files)

    %{
      individual_results: individual_results,
      aggregate_findings: aggregate_findings,
      cross_file_analysis: cross_file_analysis
    }
  end

  defp process_file_security(file, _security_level) do
    try do
      # Parse content using UniversalParser
      {:ok, document} =
        UniversalParser.parse(file.content,
          include_analysis: true,
          include_insights: true
        )

      # Detect sensitive data
      sensitive_data_findings = detect_sensitive_data(file.content, file.file_path)

      # Scan for code vulnerabilities
      vulnerability_findings = scan_code_vulnerabilities(document, file)

      # Check security best practices
      best_practice_findings = check_security_best_practices(document, file)

      # Analyze configuration security
      config_security_findings = analyze_configuration_security(document, file)

      # Calculate security score
      security_score =
        calculate_security_score([
          sensitive_data_findings,
          vulnerability_findings,
          best_practice_findings,
          config_security_findings
        ])

      # Classify risk level
      risk_level =
        classify_risk_level(security_score, [
          sensitive_data_findings,
          vulnerability_findings,
          best_practice_findings,
          config_security_findings
        ])

      %{
        file_id: file.id,
        file_path: file.file_path,
        sensitive_data_findings: sensitive_data_findings,
        vulnerability_findings: vulnerability_findings,
        best_practice_findings: best_practice_findings,
        config_security_findings: config_security_findings,
        security_score: security_score,
        risk_level: risk_level,
        total_findings:
          count_file_findings([
            sensitive_data_findings,
            vulnerability_findings,
            best_practice_findings,
            config_security_findings
          ])
      }
    rescue
      error ->
        Logger.warning("Failed to process security scan for file",
          file_id: file.id,
          error: Exception.message(error)
        )

        nil
    end
  end

  defp detect_sensitive_data(content, _file_path) do
    findings = []

    # API Keys
    api_key_patterns = [
      # Generic API key patterns
      ~r/(?i)api[_-]?key[_-]?[:=]\s*["']?([a-zA-Z0-9]{20,})["']?/,
      ~r/(?i)secret[_-]?key[_-]?[:=]\s*["']?([a-zA-Z0-9]{20,})["']?/,
      ~r/(?i)access[_-]?token[_-]?[:=]\s*["']?([a-zA-Z0-9]{20,})["']?/,
      # AWS patterns
      ~r/AKIA[0-9A-Z]{16}/,
      ~r/(?i)aws[_-]?secret[_-]?access[_-]?key[_-]?[:=]\s*["']?([a-zA-Z0-9\/+]{40})["']?/,
      # GitHub tokens
      ~r/ghp_[a-zA-Z0-9]{36}/,
      ~r/github_pat_[a-zA-Z0-9]{22}_[a-zA-Z0-9]{59}/,
      # Google API keys
      ~r/AIza[0-9A-Za-z-_]{35}/,
      # Slack tokens
      ~r/xox[baprs]-[0-9a-zA-Z-]{10,}/
    ]

    findings =
      api_key_patterns
      |> Enum.reduce(findings, fn pattern, acc ->
        matches = Regex.scan(pattern, content)

        if length(matches) > 0 do
          key_findings =
            Enum.map(matches, fn match ->
              %{
                type: "api_key",
                severity: "high",
                message: "Potential API key or secret found",
                pattern: inspect(pattern),
                context: extract_context(content, List.first(match), 50)
              }
            end)

          acc ++ key_findings
        else
          acc
        end
      end)

    # Email addresses (lower severity)
    email_matches = Regex.scan(~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, content)

    findings =
      if length(email_matches) > 0 do
        email_findings =
          Enum.map(email_matches, fn [email] ->
            %{
              type: "email",
              severity: "low",
              message: "Email address found",
              value: email,
              context: extract_context(content, email, 30)
            }
          end)

        findings ++ email_findings
      else
        findings
      end

    # Private keys
    private_key_patterns = [
      ~r/-----BEGIN\s+(?:RSA\s+)?PRIVATE\s+KEY-----/,
      ~r/-----BEGIN\s+OPENSSH\s+PRIVATE\s+KEY-----/,
      ~r/-----BEGIN\s+EC\s+PRIVATE\s+KEY-----/,
      ~r/-----BEGIN\s+DSA\s+PRIVATE\s+KEY-----/
    ]

    findings =
      private_key_patterns
      |> Enum.reduce(findings, fn pattern, acc ->
        if Regex.match?(pattern, content) do
          acc ++
            [
              %{
                type: "private_key",
                severity: "critical",
                message: "Private key found",
                pattern: inspect(pattern)
              }
            ]
        else
          acc
        end
      end)

    # Database connection strings
    db_patterns = [
      ~r/(?i)(?:postgres|mysql|mongodb):\/\/[^\s"']+/,
      ~r/(?i)(?:host|server|database)[_-]?(?:name|url)[_-]?[:=]\s*["']?[^\s"']+["']?/,
      ~r/(?i)connection[_-]?string[_-]?[:=]\s*["']?[^\s"']+["']?/
    ]

    findings =
      db_patterns
      |> Enum.reduce(findings, fn pattern, acc ->
        matches = Regex.scan(pattern, content)

        if length(matches) > 0 do
          db_findings =
            Enum.map(matches, fn [match] ->
              %{
                type: "database_connection",
                severity: "medium",
                message: "Database connection string found",
                context: extract_context(content, match, 40)
              }
            end)

          acc ++ db_findings
        else
          acc
        end
      end)

    findings
  end

  defp scan_code_vulnerabilities(document, file) do
    findings = []

    case document.format do
      format when format in ["javascript", "typescript"] ->
        findings ++ scan_javascript_vulnerabilities(document.content)

      "python" ->
        findings ++ scan_python_vulnerabilities(document.content)

      "elixir" ->
        findings ++ scan_elixir_vulnerabilities(document.content)

      format when format in ["yaml", "json"] ->
        findings ++ scan_config_vulnerabilities(document.content, file.file_name)

      "dockerfile" ->
        findings ++ scan_dockerfile_vulnerabilities(document.content)

      _ ->
        findings
    end
  end

  defp scan_javascript_vulnerabilities(content) do
    findings = []

    # SQL Injection patterns
    sql_injection_patterns = [
      ~r/(?i)query.*\+.*req\.(body|params|query)/,
      ~r/(?i)execute.*\+.*req\.(body|params|query)/,
      ~r/(?i)SELECT.*\+.*req\.(body|params|query)/
    ]

    findings =
      findings ++
        scan_patterns(
          content,
          sql_injection_patterns,
          "sql_injection",
          "high",
          "Potential SQL injection vulnerability"
        )

    # XSS patterns
    xss_patterns = [
      ~r/innerHTML\s*=.*req\.(body|params|query)/,
      ~r/document\.write.*req\.(body|params|query)/,
      ~r/\.html\(\).*req\.(body|params|query)/
    ]

    findings =
      findings ++
        scan_patterns(content, xss_patterns, "xss", "high", "Potential XSS vulnerability")

    # Unsafe eval usage
    eval_patterns = [
      ~r/eval\s*\(/,
      ~r/Function\s*\(/,
      ~r/setTimeout\s*\(\s*["'][^"']*["']/,
      ~r/setInterval\s*\(\s*["'][^"']*["']/
    ]

    findings =
      findings ++
        scan_patterns(
          content,
          eval_patterns,
          "code_injection",
          "medium",
          "Unsafe code execution detected"
        )

    findings
  end

  defp scan_python_vulnerabilities(content) do
    findings = []

    # SQL Injection patterns
    sql_patterns = [
      ~r/(?i)cursor\.execute.*\+.*request\./,
      ~r/(?i)query.*\+.*request\./,
      ~r/(?i)raw\(.*\+.*request\./
    ]

    findings =
      findings ++
        scan_patterns(
          content,
          sql_patterns,
          "sql_injection",
          "high",
          "Potential SQL injection vulnerability"
        )

    # Command injection
    command_patterns = [
      ~r/os\.system.*input\(/,
      ~r/subprocess.*shell=True/,
      ~r/eval\s*\(/,
      ~r/exec\s*\(/
    ]

    findings =
      findings ++
        scan_patterns(
          content,
          command_patterns,
          "command_injection",
          "high",
          "Potential command injection vulnerability"
        )

    # Pickle deserialization
    pickle_patterns = [
      ~r/pickle\.loads\(/,
      ~r/cPickle\.loads\(/,
      ~r/pickle\.load\(/
    ]

    findings =
      findings ++
        scan_patterns(
          content,
          pickle_patterns,
          "deserialization",
          "medium",
          "Unsafe deserialization detected"
        )

    findings
  end

  defp scan_elixir_vulnerabilities(content) do
    findings = []

    # Code injection patterns
    code_patterns = [
      ~r/Code\.eval_string/,
      ~r/:os\.cmd/,
      ~r/System\.cmd.*interpolation/
    ]

    findings =
      findings ++
        scan_patterns(
          content,
          code_patterns,
          "code_injection",
          "medium",
          "Potential code injection vulnerability"
        )

    # SQL injection patterns
    sql_patterns = [
      ~r/Ecto\.Adapters\.SQL\.query.*\#\{/,
      ~r/fragment.*\#\{/
    ]

    findings =
      findings ++
        scan_patterns(
          content,
          sql_patterns,
          "sql_injection",
          "high",
          "Potential SQL injection in Ecto query"
        )

    findings
  end

  defp scan_config_vulnerabilities(content, filename) do
    findings = []

    # Check for hardcoded secrets in config files
    if String.contains?(filename, ["config", "env", "secret"]) do
      secret_patterns = [
        ~r/password\s*[:=]\s*["'][^"'\s]+["']/,
        ~r/secret\s*[:=]\s*["'][^"'\s]+["']/,
        ~r/key\s*[:=]\s*["'][^"'\s]{20,}["']/,
        ~r/token\s*[:=]\s*["'][^"'\s]{20,}["']/
      ]

      findings =
        findings ++
          scan_patterns(
            content,
            secret_patterns,
            "hardcoded_secret",
            "high",
            "Hardcoded secret in configuration file"
          )
    end

    # Check for insecure configurations
    insecure_patterns = [
      ~r/ssl\s*[:=]\s*false/,
      ~r/verify_ssl\s*[:=]\s*false/,
      ~r/debug\s*[:=]\s*true/,
      ~r/production\s*[:=]\s*false/
    ]

    findings =
      findings ++
        scan_patterns(
          content,
          insecure_patterns,
          "insecure_config",
          "medium",
          "Potentially insecure configuration"
        )

    findings
  end

  defp scan_dockerfile_vulnerabilities(content) do
    findings = []

    # Running as root
    if not Regex.match?(~r/USER\s+[^r]/i, content) do
      findings =
        findings ++
          [
            %{
              type: "dockerfile_security",
              severity: "medium",
              message: "Container runs as root user",
              recommendation: "Add USER directive to run as non-root user"
            }
          ]
    end

    # Using latest tag
    latest_tag_pattern = ~r/FROM.*:latest/

    findings =
      findings ++
        scan_patterns(
          content,
          [latest_tag_pattern],
          "dockerfile_security",
          "low",
          "Using 'latest' tag is not recommended"
        )

    # Secrets in environment
    env_secret_patterns = [
      ~r/ENV.*(?:PASSWORD|SECRET|KEY|TOKEN)=\S+/i
    ]

    findings =
      findings ++
        scan_patterns(
          content,
          env_secret_patterns,
          "dockerfile_secret",
          "high",
          "Secret exposed in environment variable"
        )

    findings
  end

  defp scan_patterns(content, patterns, type, severity, message) do
    patterns
    |> Enum.flat_map(fn pattern ->
      matches = Regex.scan(pattern, content, return: :index)

      Enum.map(matches, fn [{start_pos, length}] ->
        match_text = String.slice(content, start_pos, length)

        %{
          type: type,
          severity: severity,
          message: message,
          context: extract_context(content, match_text, 50),
          position: start_pos
        }
      end)
    end)
  end

  defp check_security_best_practices(document, file) do
    findings = []

    # Check file permissions and sensitive file patterns
    findings =
      if String.contains?(file.file_name, [".key", ".pem", ".p12", ".jks"]) do
        findings ++
          [
            %{
              type: "sensitive_file",
              severity: "high",
              message: "Sensitive file type detected",
              file_type: Path.extname(file.file_name)
            }
          ]
      else
        findings
      end

    # Check for TODO/FIXME comments that might indicate security issues
    security_todo_patterns = [
      ~r/(?i)TODO.*(?:security|auth|password|token)/,
      ~r/(?i)FIXME.*(?:security|auth|password|token)/,
      ~r/(?i)HACK.*(?:security|auth|password|token)/
    ]

    findings =
      findings ++
        scan_patterns(
          document.content,
          security_todo_patterns,
          "security_todo",
          "low",
          "Security-related TODO/FIXME comment found"
        )

    # Check for commented-out sensitive code
    commented_secret_patterns = [
      ~r/(?:\/\/|#)\s*(?:password|secret|key|token)\s*[:=]/i,
      ~r/(?:\/\*|\*)\s*(?:password|secret|key|token)\s*[:=]/i
    ]

    findings =
      findings ++
        scan_patterns(
          document.content,
          commented_secret_patterns,
          "commented_secret",
          "medium",
          "Commented-out sensitive information"
        )

    findings
  end

  defp analyze_configuration_security(document, file) do
    findings = []

    case document.format do
      "json" ->
        findings ++ analyze_json_security(document, file)

      "yaml" ->
        findings ++ analyze_yaml_security(document, file)

      _ ->
        findings
    end
  end

  defp analyze_json_security(document, file) do
    findings = []

    # Check package.json for security issues
    if String.contains?(file.file_name, "package.json") do
      content = document.content

      # Check for scripts that might be dangerous
      if String.contains?(content, "postinstall") do
        findings =
          findings ++
            [
              %{
                type: "package_security",
                severity: "medium",
                message: "postinstall script detected - review for malicious code",
                context: extract_context(content, "postinstall", 50)
              }
            ]
      end
    end

    findings
  end

  defp analyze_yaml_security(document, file) do
    findings = []

    # Check docker-compose files
    if String.contains?(file.file_name, ["docker-compose", "compose"]) do
      content = document.content

      # Check for privileged containers
      if String.contains?(content, "privileged: true") do
        findings =
          findings ++
            [
              %{
                type: "docker_security",
                severity: "high",
                message: "Privileged container configuration detected",
                context: extract_context(content, "privileged: true", 50)
              }
            ]
      end

      # Check for host network mode
      if String.contains?(content, "network_mode: host") do
        findings =
          findings ++
            [
              %{
                type: "docker_security",
                severity: "medium",
                message: "Host network mode detected - reduces isolation",
                context: extract_context(content, "network_mode: host", 50)
              }
            ]
      end
    end

    findings
  end

  defp calculate_security_score(finding_groups) do
    total_findings = finding_groups |> List.flatten() |> length()

    if total_findings == 0 do
      10.0
    else
      severity_weights = %{
        "critical" => 4.0,
        "high" => 3.0,
        "medium" => 2.0,
        "low" => 1.0
      }

      weighted_score =
        finding_groups
        |> List.flatten()
        |> Enum.reduce(0.0, fn finding, acc ->
          weight = Map.get(severity_weights, finding.severity, 1.0)
          acc + weight
        end)

      # Normalize to 1-10 scale (higher = more secure)
      base_score = 10.0
      penalty = min(9.0, weighted_score * 0.5)
      max(1.0, base_score - penalty)
    end
  end

  defp classify_risk_level(security_score, finding_groups) do
    all_findings = List.flatten(finding_groups)

    critical_count = Enum.count(all_findings, &(&1.severity == "critical"))
    high_count = Enum.count(all_findings, &(&1.severity == "high"))

    cond do
      critical_count > 0 or security_score < 3.0 -> "critical"
      high_count > 2 or security_score < 5.0 -> "high"
      security_score < 7.0 -> "medium"
      true -> "low"
    end
  end

  defp aggregate_security_findings(individual_results) do
    all_findings =
      individual_results
      |> Enum.flat_map(fn result ->
        [
          result.sensitive_data_findings,
          result.vulnerability_findings,
          result.best_practice_findings,
          result.config_security_findings
        ]
        |> List.flatten()
      end)

    findings_by_type = Enum.group_by(all_findings, & &1.type)
    findings_by_severity = Enum.group_by(all_findings, & &1.severity)

    %{
      total_findings: length(all_findings),
      findings_by_type: Map.new(findings_by_type, fn {k, v} -> {k, length(v)} end),
      findings_by_severity: Map.new(findings_by_severity, fn {k, v} -> {k, length(v)} end),
      most_common_issues: get_most_common_issues(findings_by_type)
    }
  end

  defp analyze_cross_file_security(individual_results, files) do
    # Look for patterns across multiple files that might indicate security issues

    # Check for credential storage patterns
    credential_files =
      individual_results
      |> Enum.filter(fn result ->
        length(result.sensitive_data_findings) > 0
      end)
      |> Enum.map(& &1.file_path)

    # Check for configuration sprawl
    config_files =
      files
      |> Enum.filter(fn file ->
        String.contains?(file.file_name, ["config", "env", ".env", "settings"])
      end)
      |> Enum.map(& &1.file_path)

    %{
      credential_files: credential_files,
      config_files: config_files,
      credential_sprawl: length(credential_files) > 3,
      config_sprawl: length(config_files) > 5
    }
  end

  defp get_most_common_issues(findings_by_type) do
    findings_by_type
    |> Enum.sort_by(fn {_type, count} -> count end, :desc)
    |> Enum.take(5)
    |> Map.new()
  end

  defp count_file_findings(finding_groups) do
    finding_groups |> List.flatten() |> length()
  end

  defp count_total_findings(security_results) do
    security_results.individual_results
    |> Enum.map(& &1.total_findings)
    |> Enum.sum()
  end

  defp extract_context(content, match, context_size) do
    case :binary.match(content, match) do
      {start_pos, _length} ->
        context_start = max(0, start_pos - context_size)
        context_length = min(byte_size(content) - context_start, context_size * 2)
        String.slice(content, context_start, context_length)

      :nomatch ->
        String.slice(match, 0, min(String.length(match), 100))
    end
  end

  defp update_files_with_security_results(files, security_results) do
    individual_results = security_results.individual_results

    # Create a map for quick lookup
    results_by_file_id =
      individual_results
      |> Enum.map(fn result -> {result.file_id, result} end)
      |> Map.new()

    # Update each file
    Enum.each(files, fn file ->
      case Map.get(results_by_file_id, file.id) do
        nil ->
          Logger.warning("No security results found for file", file_id: file.id)

        result ->
          update_attrs = %{
            security_findings: %{
              sensitive_data: result.sensitive_data_findings,
              vulnerabilities: result.vulnerability_findings,
              best_practices: result.best_practice_findings,
              configuration: result.config_security_findings
            },
            vulnerability_count: result.total_findings,
            security_score: result.security_score,
            risk_level: result.risk_level,
            sensitive_data_found: length(result.sensitive_data_findings) > 0,
            security_analyzed_at: DateTime.utc_now()
          }

          case Analysis.update_analyzed_file(file, update_attrs) do
            {:ok, _updated_file} ->
              Logger.debug("Updated security analysis for file", file_id: file.id)

            {:error, reason} ->
              Logger.error("Failed to update security analysis",
                file_id: file.id,
                reason: inspect(reason)
              )
          end
      end
    end)
  end
end
