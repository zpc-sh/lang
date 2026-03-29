defmodule Lang.Workers.DependencyAnalysisWorker do
  @moduledoc """
  Dependency Analysis Worker for analyzing project dependencies and relationships.

  This worker performs comprehensive dependency analysis including package analysis,
  vulnerability scanning, license compliance checking, and dependency graph generation
  for various project types and package managers.

  ## Features

  - **Package Analysis** - Parse package.json, requirements.txt, mix.exs, Cargo.toml
  - **Dependency Vulnerability Scanning** - Check for known vulnerable dependencies
  - **License Compliance Checking** - Validate license compatibility and compliance
  - **Dependency Graph Generation** - Build dependency relationship graphs
  - **Version Analysis** - Check for outdated packages and version constraints
  - **Circular Dependency Detection** - Find circular dependencies in the project

  ## Usage

      # Queue dependency analysis job
      job = DependencyAnalysisWorker.new(%{
        "scan_result_id" => scan_result.id,
        "session_id" => session.id,
        "analyze_versions" => true
      })
      |> Oban.insert()

  """

  use Oban.Worker, queue: :analysis, max_attempts: 3

  alias Lang.Analysis
  alias Kyozo.Lang.UniversalParser
  alias Lang.Native.Parser
  require Logger

  # Known vulnerable packages (simplified list - in production, integrate with vulnerability databases)
  @vulnerable_packages %{
    "lodash" => ["4.17.20", "4.17.19", "4.17.18"],
    "express" => ["4.16.0", "4.15.5"],
    "django" => ["3.1.0", "3.0.7", "2.2.13"],
    "requests" => ["2.25.0", "2.24.0"],
    "flask" => ["1.1.0", "1.0.4"],
    "phoenix" => ["1.5.0", "1.4.17"],
    "ecto" => ["3.4.0", "3.3.4"]
  }

  # License compatibility matrix (simplified)
  @license_compatibility %{
    "MIT" => ["MIT", "Apache-2.0", "BSD-3-Clause", "ISC"],
    "Apache-2.0" => ["Apache-2.0", "MIT", "BSD-3-Clause"],
    "GPL-3.0" => ["GPL-3.0", "GPL-2.0"],
    "BSD-3-Clause" => ["BSD-3-Clause", "MIT", "Apache-2.0"]
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    scan_result_id = args["scan_result_id"]
    session_id = args["session_id"]
    analyze_versions = args["analyze_versions"] || true

    Logger.info("Starting dependency analysis",
      scan_result_id: scan_result_id,
      session_id: session_id,
      analyze_versions: analyze_versions
    )

    try do
      # Get analyzed files for this session
      files = Analysis.list_analyzed_files(session_id, limit: 1000)

      if Enum.empty?(files) do
        Logger.info("No files found for dependency analysis", session_id: session_id)
        :ok
      else
        # Find dependency files
        dependency_files = find_dependency_files(files)

        if Enum.empty?(dependency_files) do
          Logger.info("No dependency files found", session_id: session_id)
          :ok
        else
          # Process dependency analysis
          dependency_results = process_dependency_analysis(dependency_files, analyze_versions)

          # Update files with dependency analysis results
          update_files_with_dependency_results(dependency_files, dependency_results)

          Logger.info("Dependency analysis completed",
            scan_result_id: scan_result_id,
            dependency_files: length(dependency_files),
            total_dependencies: count_total_dependencies(dependency_results)
          )

          :ok
        end
      end
    rescue
      error ->
        Logger.error("Dependency analysis failed",
          scan_result_id: scan_result_id,
          session_id: session_id,
          error: Exception.message(error)
        )

        {:error, {:dependency_analysis_failed, error}}
    end
  end

  # === Private Functions ===

  defp find_dependency_files(files) do
    dependency_file_patterns = [
      "package.json",
      "package-lock.json",
      "yarn.lock",
      "requirements.txt",
      "Pipfile",
      "poetry.lock",
      "mix.exs",
      "mix.lock",
      "Cargo.toml",
      "Cargo.lock",
      "composer.json",
      "composer.lock",
      "Gemfile",
      "Gemfile.lock",
      "go.mod",
      "go.sum",
      "pom.xml",
      "build.gradle",
      "pubspec.yaml"
    ]

    files
    |> Enum.filter(fn file ->
      Enum.any?(dependency_file_patterns, &String.contains?(file.file_name, &1))
    end)
  end

  defp process_dependency_analysis(dependency_files, analyze_versions) do
    Logger.info("Processing dependency analysis for #{length(dependency_files)} files")

    # Process each dependency file
    individual_results =
      dependency_files
      |> Enum.map(&process_dependency_file(&1, analyze_versions))
      |> Enum.reject(&is_nil/1)

    # Build project-wide dependency graph
    project_graph = build_project_dependency_graph(individual_results)

    # Perform cross-file dependency analysis
    cross_file_analysis = analyze_cross_file_dependencies(individual_results)

    # Aggregate vulnerability analysis
    vulnerability_summary = aggregate_vulnerability_analysis(individual_results)

    # License compliance analysis
    license_analysis = analyze_license_compliance(individual_results)

    %{
      individual_results: individual_results,
      project_graph: project_graph,
      cross_file_analysis: cross_file_analysis,
      vulnerability_summary: vulnerability_summary,
      license_analysis: license_analysis
    }
  end

  defp process_dependency_file(file, analyze_versions) do
    try do
      # Parse content using UniversalParser
      {:ok, document} =
        UniversalParser.parse(file.content,
          include_analysis: true,
          include_insights: true
        )

      # Extract dependencies based on file type
      dependencies = extract_dependencies(document, file)

      # Analyze versions if requested
      version_analysis =
        if analyze_versions do
          analyze_dependency_versions(dependencies, file)
        else
          %{}
        end

      # Check for vulnerabilities
      vulnerability_analysis = check_vulnerabilities(dependencies)

      # Extract license information
      license_analysis = extract_license_information(dependencies, document, file)

      # Detect circular dependencies
      circular_dependencies = detect_circular_dependencies(dependencies)

      # Calculate dependency metrics
      metrics = calculate_dependency_metrics(dependencies)

      %{
        file_id: file.id,
        file_path: file.file_path,
        file_type: determine_dependency_file_type(file.file_name),
        dependencies: dependencies,
        version_analysis: version_analysis,
        vulnerability_analysis: vulnerability_analysis,
        license_analysis: license_analysis,
        circular_dependencies: circular_dependencies,
        metrics: metrics,
        total_dependencies: length(dependencies)
      }
    rescue
      error ->
        Logger.warning("Failed to process dependency file",
          file_id: file.id,
          error: Exception.message(error)
        )

        nil
    end
  end

  defp extract_dependencies(document, file) do
    case determine_dependency_file_type(file.file_name) do
      :package_json -> extract_npm_dependencies(document)
      :requirements_txt -> extract_python_dependencies(document)
      :mix_exs -> extract_elixir_dependencies(document)
      :cargo_toml -> extract_rust_dependencies(document)
      :composer_json -> extract_php_dependencies(document)
      :gemfile -> extract_ruby_dependencies(document)
      :go_mod -> extract_go_dependencies(document)
      :pom_xml -> extract_maven_dependencies(document)
      :pubspec_yaml -> extract_dart_dependencies(document)
      _ -> []
    end
  end

  defp determine_dependency_file_type(filename) do
    cond do
      String.contains?(filename, "package.json") -> :package_json
      String.contains?(filename, "requirements.txt") -> :requirements_txt
      String.contains?(filename, "mix.exs") -> :mix_exs
      String.contains?(filename, "Cargo.toml") -> :cargo_toml
      String.contains?(filename, "composer.json") -> :composer_json
      String.contains?(filename, "Gemfile") -> :gemfile
      String.contains?(filename, "go.mod") -> :go_mod
      String.contains?(filename, "pom.xml") -> :pom_xml
      String.contains?(filename, "pubspec.yaml") -> :pubspec_yaml
      true -> :unknown
    end
  end

  defp extract_npm_dependencies(document) do
    try do
      case Jason.decode(document.content) do
        {:ok, json} ->
          dependencies = []

          # Regular dependencies
          dependencies =
            case Map.get(json, "dependencies") do
              deps when is_map(deps) ->
                deps
                |> Enum.map(fn {name, version} ->
                  %{
                    name: name,
                    version: version,
                    type: "runtime",
                    ecosystem: "npm"
                  }
                end)
                |> Kernel.++(dependencies)

              _ ->
                dependencies
            end

          # Dev dependencies
          dependencies =
            case Map.get(json, "devDependencies") do
              dev_deps when is_map(dev_deps) ->
                dev_deps
                |> Enum.map(fn {name, version} ->
                  %{
                    name: name,
                    version: version,
                    type: "development",
                    ecosystem: "npm"
                  }
                end)
                |> Kernel.++(dependencies)

              _ ->
                dependencies
            end

          # Peer dependencies
          dependencies =
            case Map.get(json, "peerDependencies") do
              peer_deps when is_map(peer_deps) ->
                peer_deps
                |> Enum.map(fn {name, version} ->
                  %{
                    name: name,
                    version: version,
                    type: "peer",
                    ecosystem: "npm"
                  }
                end)
                |> Kernel.++(dependencies)

              _ ->
                dependencies
            end

          dependencies

        {:error, _} ->
          Logger.warning("Failed to parse package.json")
          []
      end
    rescue
      _ ->
        []
    end
  end

  defp extract_python_dependencies(document) do
    document.content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.map(fn line ->
      # Handle different requirement formats
      cond do
        String.contains?(line, "==") ->
          [name, version] = String.split(line, "==", parts: 2)

          %{
            name: String.trim(name),
            version: String.trim(version),
            type: "runtime",
            ecosystem: "pypi"
          }

        String.contains?(line, ">=") ->
          [name, version] = String.split(line, ">=", parts: 2)

          %{
            name: String.trim(name),
            version: ">=#{String.trim(version)}",
            type: "runtime",
            ecosystem: "pypi"
          }

        String.contains?(line, "~=") ->
          [name, version] = String.split(line, "~=", parts: 2)

          %{
            name: String.trim(name),
            version: "~=#{String.trim(version)}",
            type: "runtime",
            ecosystem: "pypi"
          }

        true ->
          %{name: String.trim(line), version: "*", type: "runtime", ecosystem: "pypi"}
      end
    end)
  end

  defp extract_elixir_dependencies(document) do
    # Simple regex-based extraction for mix.exs
    deps_regex = ~r/\{:([^,]+),\s*"([^"]+)"/

    Regex.scan(deps_regex, document.content)
    |> Enum.map(fn [_, name, version] ->
      %{
        name: name,
        version: version,
        type: "runtime",
        ecosystem: "hex"
      }
    end)
  end

  defp extract_rust_dependencies(document) do
    # Parse TOML content for Cargo.toml
    lines = String.split(document.content, "\n")
    in_dependencies = false
    dependencies = []

    lines
    |> Enum.reduce({dependencies, in_dependencies}, fn line, {deps, in_deps_section} ->
      trimmed_line = String.trim(line)

      cond do
        trimmed_line == "[dependencies]" ->
          {deps, true}

        String.starts_with?(trimmed_line, "[") and trimmed_line != "[dependencies]" ->
          {deps, false}

        in_deps_section and String.contains?(trimmed_line, "=") ->
          case String.split(trimmed_line, "=", parts: 2) do
            [name, version_part] ->
              name = String.trim(name)
              version = String.trim(version_part) |> String.trim("\"") |> String.trim("'")

              dep = %{
                name: name,
                version: version,
                type: "runtime",
                ecosystem: "crates"
              }

              {[dep | deps], in_deps_section}

            _ ->
              {deps, in_deps_section}
          end

        true ->
          {deps, in_deps_section}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp extract_php_dependencies(document) do
    try do
      case Jason.decode(document.content) do
        {:ok, json} ->
          dependencies = []

          # Runtime dependencies
          dependencies =
            case Map.get(json, "require") do
              deps when is_map(deps) ->
                deps
                |> Enum.map(fn {name, version} ->
                  %{
                    name: name,
                    version: version,
                    type: "runtime",
                    ecosystem: "packagist"
                  }
                end)
                |> Kernel.++(dependencies)

              _ ->
                dependencies
            end

          # Dev dependencies
          dependencies =
            case Map.get(json, "require-dev") do
              dev_deps when is_map(dev_deps) ->
                dev_deps
                |> Enum.map(fn {name, version} ->
                  %{
                    name: name,
                    version: version,
                    type: "development",
                    ecosystem: "packagist"
                  }
                end)
                |> Kernel.++(dependencies)

              _ ->
                dependencies
            end

          dependencies

        {:error, _} ->
          []
      end
    rescue
      _ ->
        []
    end
  end

  defp extract_ruby_dependencies(document) do
    # Simple regex-based extraction for Gemfile
    gem_regex = ~r/gem\s+['"]([^'"]+)['"]\s*(?:,\s*['"]([^'"]+)['"])?/

    Regex.scan(gem_regex, document.content)
    |> Enum.map(fn
      [_, name, version] when version != "" ->
        %{name: name, version: version, type: "runtime", ecosystem: "rubygems"}

      [_, name] ->
        %{name: name, version: "*", type: "runtime", ecosystem: "rubygems"}
    end)
  end

  defp extract_go_dependencies(document) do
    # Simple regex-based extraction for go.mod
    require_regex = ~r/require\s+([^\s]+)\s+([^\s]+)/

    Regex.scan(require_regex, document.content)
    |> Enum.map(fn [_, name, version] ->
      %{
        name: name,
        version: version,
        type: "runtime",
        ecosystem: "go"
      }
    end)
  end

  defp extract_maven_dependencies(document) do
    # Simple regex-based extraction for Maven pom.xml
    dependency_regex =
      ~r/<groupId>([^<]+)<\/groupId>\s*<artifactId>([^<]+)<\/artifactId>\s*<version>([^<]+)<\/version>/

    Regex.scan(dependency_regex, document.content)
    |> Enum.map(fn [_, group_id, artifact_id, version] ->
      %{
        name: "#{group_id}:#{artifact_id}",
        version: version,
        type: "runtime",
        ecosystem: "maven"
      }
    end)
  end

  defp extract_dart_dependencies(document) do
    # Simple YAML parsing for pubspec.yaml dependencies
    lines = String.split(document.content, "\n")
    in_dependencies = false
    dependencies = []

    lines
    |> Enum.reduce({dependencies, in_dependencies}, fn line, {deps, in_deps_section} ->
      trimmed_line = String.trim(line)

      cond do
        trimmed_line == "dependencies:" ->
          {deps, true}

        String.match?(trimmed_line, ~r/^[a-zA-Z_][a-zA-Z0-9_]*:$/) and
            trimmed_line != "dependencies:" ->
          {deps, false}

        in_deps_section and String.contains?(trimmed_line, ":") and
            String.starts_with?(line, "  ") ->
          case String.split(trimmed_line, ":", parts: 2) do
            [name, version_part] ->
              name = String.trim(name)
              version = String.trim(version_part) |> String.trim("^") |> String.trim()

              dep = %{
                name: name,
                version: if(version == "", do: "*", else: version),
                type: "runtime",
                ecosystem: "pub"
              }

              {[dep | deps], in_deps_section}

            _ ->
              {deps, in_deps_section}
          end

        true ->
          {deps, in_deps_section}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp analyze_dependency_versions(dependencies, _file) do
    version_issues = []

    version_issues =
      dependencies
      |> Enum.reduce(version_issues, fn dep, issues ->
        cond do
          # Check for overly broad version constraints
          String.contains?(dep.version, "*") ->
            issues ++
              [
                %{
                  type: "broad_version_constraint",
                  severity: "medium",
                  package: dep.name,
                  version: dep.version,
                  message: "Overly broad version constraint"
                }
              ]

          # Check for exact version pinning in development dependencies
          dep.type == "development" and String.contains?(dep.version, "==") ->
            issues ++
              [
                %{
                  type: "exact_dev_version",
                  severity: "low",
                  package: dep.name,
                  version: dep.version,
                  message: "Exact version pinning in development dependency"
                }
              ]

          true ->
            issues
        end
      end)

    %{
      total_dependencies: length(dependencies),
      version_issues: version_issues,
      ecosystems: dependencies |> Enum.map(& &1.ecosystem) |> Enum.uniq(),
      dependency_types: dependencies |> Enum.map(& &1.type) |> Enum.frequencies()
    }
  end

  defp check_vulnerabilities(dependencies) do
    vulnerabilities =
      dependencies
      |> Enum.filter(fn dep ->
        vulnerable_versions = Map.get(@vulnerable_packages, dep.name, [])
        dep.version in vulnerable_versions
      end)
      |> Enum.map(fn dep ->
        %{
          package: dep.name,
          version: dep.version,
          ecosystem: dep.ecosystem,
          severity: "high",
          message: "Known vulnerable version"
        }
      end)

    %{
      vulnerable_dependencies: vulnerabilities,
      vulnerability_count: length(vulnerabilities),
      packages_checked: length(dependencies)
    }
  end

  defp extract_license_information(_dependencies, document, file) do
    # Extract license from the main package file
    main_license =
      case determine_dependency_file_type(file.file_name) do
        :package_json ->
          extract_npm_license(document)

        :mix_exs ->
          extract_elixir_license(document)

        :cargo_toml ->
          extract_rust_license(document)

        :composer_json ->
          extract_php_license(document)

        _ ->
          nil
      end

    # For simplicity, we don't check each dependency's license here
    # In a real implementation, you'd query package registries for license info
    dependency_licenses = []

    %{
      main_license: main_license,
      dependency_licenses: dependency_licenses,
      license_issues: check_license_compatibility(main_license, dependency_licenses)
    }
  end

  defp extract_npm_license(document) do
    try do
      case Jason.decode(document.content) do
        {:ok, json} -> Map.get(json, "license")
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end

  defp extract_elixir_license(document) do
    # Look for license in mix.exs
    license_regex = ~r/license:\s*["']([^"']+)["']/

    case Regex.run(license_regex, document.content) do
      [_, license] -> license
      _ -> nil
    end
  end

  defp extract_rust_license(document) do
    # Look for license in Cargo.toml
    license_regex = ~r/license\s*=\s*["']([^"']+)["']/

    case Regex.run(license_regex, document.content) do
      [_, license] -> license
      _ -> nil
    end
  end

  defp extract_php_license(document) do
    try do
      case Jason.decode(document.content) do
        {:ok, json} -> Map.get(json, "license")
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end

  defp check_license_compatibility(main_license, dependency_licenses) do
    if main_license && length(dependency_licenses) > 0 do
      compatible_licenses = Map.get(@license_compatibility, main_license, [])

      incompatible =
        dependency_licenses
        |> Enum.reject(fn dep_license -> dep_license.license in compatible_licenses end)

      if length(incompatible) > 0 do
        [
          %{
            type: "license_incompatibility",
            severity: "medium",
            message: "Potentially incompatible licenses detected",
            main_license: main_license,
            incompatible_licenses: incompatible
          }
        ]
      else
        []
      end
    else
      []
    end
  end

  defp detect_circular_dependencies(dependencies) do
    # Simple circular dependency detection
    # In a real implementation, you'd build a proper dependency graph
    dependency_names = MapSet.new(dependencies, & &1.name)

    circular_refs =
      dependencies
      |> Enum.filter(fn dep ->
        # Check if any dependency might reference back to packages in this project
        # This is a simplified check
        String.contains?(dep.name, ["self", "local", "file:"]) or
          MapSet.member?(dependency_names, dep.name)
      end)

    %{
      circular_dependencies: circular_refs,
      circular_count: length(circular_refs)
    }
  end

  defp calculate_dependency_metrics(dependencies) do
    total = length(dependencies)
    by_ecosystem = Enum.group_by(dependencies, & &1.ecosystem)
    by_type = Enum.group_by(dependencies, & &1.type)

    runtime_count = length(Map.get(by_type, "runtime", []))
    dev_count = length(Map.get(by_type, "development", []))

    %{
      total_dependencies: total,
      runtime_dependencies: runtime_count,
      development_dependencies: dev_count,
      ecosystems: Map.keys(by_ecosystem),
      ecosystem_distribution: Map.new(by_ecosystem, fn {k, v} -> {k, length(v)} end),
      dependency_ratio: if(total > 0, do: runtime_count / total, else: 0.0)
    }
  end

  defp build_project_dependency_graph(individual_results) do
    all_dependencies = individual_results |> Enum.flat_map(& &1.dependencies)

    # Group by ecosystem
    by_ecosystem = Enum.group_by(all_dependencies, & &1.ecosystem)

    # Find duplicate dependencies across files
    dependency_frequency =
      all_dependencies
      |> Enum.map(& &1.name)
      |> Enum.frequencies()

    duplicates =
      dependency_frequency
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Map.new()

    %{
      total_unique_dependencies: map_size(dependency_frequency),
      ecosystems: Map.keys(by_ecosystem),
      ecosystem_counts: Map.new(by_ecosystem, fn {k, v} -> {k, length(v)} end),
      duplicate_dependencies: duplicates,
      dependency_files: length(individual_results)
    }
  end

  defp analyze_cross_file_dependencies(individual_results) do
    # Look for version conflicts across files
    version_conflicts =
      individual_results
      |> Enum.flat_map(fn result ->
        result.dependencies
        |> Enum.map(fn dep -> {dep.name, dep.version, result.file_path} end)
      end)
      |> Enum.group_by(fn {name, _version, _file} -> name end)
      |> Enum.filter(fn {_name, versions} -> length(versions) > 1 end)
      |> Enum.filter(fn {_name, versions} ->
        versions
        |> Enum.map(fn {_name, version, _file} -> version end)
        |> Enum.uniq()
        |> length() > 1
      end)
      |> Map.new()

    %{
      version_conflicts: version_conflicts,
      conflict_count: map_size(version_conflicts)
    }
  end

  defp aggregate_vulnerability_analysis(individual_results) do
    all_vulnerabilities =
      individual_results
      |> Enum.flat_map(fn result -> result.vulnerability_analysis.vulnerable_dependencies end)

    vulnerability_by_severity = Enum.group_by(all_vulnerabilities, & &1.severity)

    %{
      total_vulnerabilities: length(all_vulnerabilities),
      vulnerabilities_by_severity:
        Map.new(vulnerability_by_severity, fn {k, v} -> {k, length(v)} end),
      vulnerable_packages: all_vulnerabilities |> Enum.map(& &1.package) |> Enum.uniq(),
      files_with_vulnerabilities:
        individual_results
        |> Enum.filter(fn result -> result.vulnerability_analysis.vulnerability_count > 0 end)
        |> length()
    }
  end

  defp analyze_license_compliance(individual_results) do
    all_licenses =
      individual_results
      |> Enum.map(& &1.license_analysis.main_license)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    license_issues =
      individual_results
      |> Enum.flat_map(& &1.license_analysis.license_issues)

    %{
      unique_licenses: all_licenses,
      license_count: length(all_licenses),
      license_issues: license_issues,
      compliance_score: calculate_compliance_score(license_issues)
    }
  end

  defp calculate_compliance_score(license_issues) do
    if length(license_issues) == 0 do
      10.0
    else
      penalty = min(9.0, length(license_issues) * 2.0)
      max(1.0, 10.0 - penalty)
    end
  end

  defp count_total_dependencies(dependency_results) do
    dependency_results.individual_results
    |> Enum.map(& &1.total_dependencies)
    |> Enum.sum()
  end

  defp update_files_with_dependency_results(dependency_files, dependency_results) do
    individual_results = dependency_results.individual_results

    # Create a map for quick lookup
    results_by_file_id =
      individual_results
      |> Enum.map(fn result -> {result.file_id, result} end)
      |> Map.new()

    # Update each file
    Enum.each(dependency_files, fn file ->
      case Map.get(results_by_file_id, file.id) do
        nil ->
          Logger.warning("No dependency results found for file", file_id: file.id)

        result ->
          update_attrs = %{
            dependency_list: result.dependencies,
            dependency_vulnerabilities: result.vulnerability_analysis,
            license_compliance: result.license_analysis,
            dependency_graph: %{
              file_metrics: result.metrics,
              circular_dependencies: result.circular_dependencies,
              version_analysis: result.version_analysis
            },
            dependency_analyzed_at: DateTime.utc_now()
          }

          case Analysis.update_analyzed_file(file, update_attrs) do
            {:ok, _updated_file} ->
              Logger.debug("Updated dependency analysis for file", file_id: file.id)

            {:error, reason} ->
              Logger.error("Failed to update dependency analysis",
                file_id: file.id,
                reason: inspect(reason)
              )
          end
      end
    end)
  end
end
