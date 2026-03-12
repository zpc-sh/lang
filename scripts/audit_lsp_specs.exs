#!/usr/bin/env elixir

# Script to audit all LSP method specifications and their implementations
# Run with: elixir scripts/audit_lsp_specs.exs

defmodule LSPSpecAuditor do
  @moduledoc """
  Audits LSP method specifications against their implementations
  """

  @spec_dir "priv/lsp/specs"
  @categories %{
    "agent" => "Agent coordination and management",
    "analyze" => "Code analysis operations",
    "fs" => "Filesystem operations",
    "generate" => "Code generation",
    "graph" => "Knowledge graph operations",
    "metrics" => "Metrics and performance tracking",
    "orchestration" => "Task orchestration",
    "parser" => "Code parsing",
    "query" => "Query operations",
    "security" => "Security operations",
    "spatial" => "Spatial code navigation",
    "storage" => "Storage operations",
    "think" => "AI-powered analysis",
    "timeline" => "Timeline and history operations",
    "tokens" => "Token management",
    "workspace" => "Workspace management",
    "mcp" => "MCP connection management",
    "rpc" => "RPC operations",
    "textDocument" => "Standard LSP text document operations"
  }

  def run do
    IO.puts("\n🔍 Lang LSP Method Implementation Audit")
    IO.puts("=" |> String.duplicate(80))

    specs = load_all_specs()

    IO.puts("\n📊 Summary:")
    IO.puts("Total methods: #{length(specs)}")

    # Group by category
    by_category = Enum.group_by(specs, & &1["category"])

    IO.puts("\n📁 Methods by Category:")

    Enum.each(@categories, fn {category, description} ->
      methods = Map.get(by_category, category, [])
      IO.puts("  #{category}: #{length(methods)} methods - #{description}")
    end)

    # Group by status
    by_status =
      Enum.group_by(specs, fn spec ->
        get_in(spec, ["implementation", "status"]) || "not_started"
      end)

    IO.puts("\n📈 Implementation Status:")
    IO.puts("  ✅ Implemented: #{length(Map.get(by_status, "implemented", []))}")
    IO.puts("  🚧 In Progress: #{length(Map.get(by_status, "in_progress", []))}")
    IO.puts("  ❌ Not Started: #{length(Map.get(by_status, "not_started", []))}")

    # Check each category in detail
    IO.puts("\n🔎 Detailed Analysis by Category:")
    IO.puts("=" |> String.duplicate(80))

    Enum.each(@categories, fn {category, _description} ->
      methods = Map.get(by_category, category, [])

      if length(methods) > 0 do
        analyze_category(category, methods)
      end
    end)

    # Find methods that need immediate attention
    IO.puts("\n⚠️  Critical Methods Needing Implementation:")
    IO.puts("=" |> String.duplicate(80))

    critical_not_implemented =
      specs
      |> Enum.filter(fn spec ->
        priority = get_in(spec, ["implementation", "priority"])
        status = get_in(spec, ["implementation", "status"])
        priority == "Critical" && status != "implemented"
      end)
      |> Enum.sort_by(& &1["name"])

    Enum.each(critical_not_implemented, fn spec ->
      IO.puts("  #{spec["name"]}")
      IO.puts("    Status: #{get_in(spec, ["implementation", "status"])}")
      IO.puts("    File: #{get_in(spec, ["implementation", "file"])}")
      IO.puts("    Description: #{spec["description"]}")
      IO.puts("")
    end)

    # Generate implementation checklist
    generate_implementation_checklist(specs)
  end

  defp load_all_specs do
    spec_files =
      Path.wildcard("#{@spec_dir}/**/*.jsonld")
      |> Enum.sort()

    Enum.map(spec_files, fn file ->
      File.read!(file)
      |> Jason.decode!()
    end)
  end

  defp analyze_category(category, methods) do
    IO.puts("\n#{String.upcase(category)} Methods:")

    grouped =
      Enum.group_by(methods, fn method ->
        get_in(method, ["implementation", "status"]) || "not_started"
      end)

    implemented = Map.get(grouped, "implemented", [])
    in_progress = Map.get(grouped, "in_progress", [])
    not_started = Map.get(grouped, "not_started", [])

    IO.puts(
      "  Status: ✅ #{length(implemented)} | 🚧 #{length(in_progress)} | ❌ #{length(not_started)}"
    )

    # Check if implementation files exist
    all_files =
      methods
      |> Enum.map(fn m -> get_in(m, ["implementation", "file"]) end)
      |> Enum.filter(& &1)
      |> Enum.uniq()

    existing_files = Enum.filter(all_files, &File.exists?/1)
    missing_files = all_files -- existing_files

    if length(missing_files) > 0 do
      IO.puts("  ⚠️  Missing implementation files:")

      Enum.each(missing_files, fn file ->
        IO.puts("    - #{file}")
      end)
    end

    # List methods by status
    if length(not_started) > 0 do
      IO.puts("  ❌ Not Started:")

      Enum.each(Enum.take(not_started, 5), fn method ->
        IO.puts("    - #{method["name"]}")
      end)

      if length(not_started) > 5 do
        IO.puts("    ... and #{length(not_started) - 5} more")
      end
    end

    if length(in_progress) > 0 do
      IO.puts("  🚧 In Progress:")

      Enum.each(in_progress, fn method ->
        IO.puts("    - #{method["name"]} (#{method["description"]})")
      end)
    end
  end

  defp generate_implementation_checklist(specs) do
    IO.puts("\n📋 Implementation Checklist:")
    IO.puts("=" |> String.duplicate(80))

    # Group by implementation file
    by_file =
      specs
      |> Enum.filter(fn spec ->
        status = get_in(spec, ["implementation", "status"])
        status != "implemented"
      end)
      |> Enum.group_by(fn spec ->
        get_in(spec, ["implementation", "file"]) || "unknown"
      end)

    Enum.each(by_file, fn {file, methods} ->
      IO.puts("\n#{file}:")

      Enum.each(methods, fn method ->
        status_icon =
          case get_in(method, ["implementation", "status"]) do
            "in_progress" -> "🚧"
            _ -> "❌"
          end

        IO.puts("  #{status_icon} #{method["name"]}")

        # Suggest implementation based on method name
        suggest_implementation(method)
      end)
    end)
  end

  defp suggest_implementation(method) do
    name = method["name"]
    category = method["category"]

    suggestion =
      case category do
        "think" ->
          "    → Route to AI provider with appropriate prompt"

        "generate" ->
          "    → Create Oban worker and route to AI provider"

        "fs" ->
          "    → Use Lang.Native.FSScanner for filesystem operations"

        "analyze" ->
          "    → Use Lang.TextIntelligence.AnalysisEngine"

        "storage" ->
          "    → Implement with Kyozo storage backend"

        "agent" ->
          "    → Implement in Lang.Agent.Runtime or appropriate module"

        "spatial" ->
          "    → Use Lang.Spatial.Map for code navigation"

        "timeline" ->
          "    → Implement with Lang.TimeMachine"

        "tokens" ->
          "    → Implement token counting/optimization logic"

        "graph" ->
          "    → Use knowledge graph with Lang.Graph"

        _ ->
          "    → Implement appropriate logic"
      end

    IO.puts(suggestion)
  end
end

# Run the audit
LSPSpecAuditor.run()
