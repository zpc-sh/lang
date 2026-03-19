defmodule LangWeb.Testing.LSPComparatorLive do
  @moduledoc """
  LiveView interface for managing and monitoring LSP comparison tests.

  This interface allows users to:
  - Configure and start LSP comparison test sessions
  - Monitor real-time progress of running tests
  - View detailed results and performance analysis
  - Compare different agent variants and scenarios
  """

  use LangWeb, :live_view

  alias Lang.Testing.{
    LSPComparator,
    ScenarioDefinitions,
    AgentVariantGenerator,
    PerformanceAnalyzer
  }

  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to comparison updates
      PubSub.subscribe(Lang.PubSub, "lsp_comparison_global")
    end

    socket =
      socket
      |> assign(:page_title, "LSP Performance Testing")
      |> assign(:current_page, :lsp_comparator)
      |> assign(:test_sessions, [])
      |> assign(:available_scenarios, ScenarioDefinitions.list_scenarios())
      |> assign(:available_variants, AgentVariantGenerator.list_variants())
      |> assign(:current_session, nil)
      |> assign(:show_config_modal, false)
      |> assign(:show_results_modal, false)
      |> assign(:selected_scenarios, [])
      |> assign(:selected_variants, [])
      |> assign(:test_config, %{
        parallel_tests: 4,
        timeout_minutes: 60,
        significance_threshold: 0.05
      })
      |> assign(:results_data, nil)
      |> assign(:analysis_data, nil)
      |> load_recent_sessions()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_config_modal", _params, socket) do
    {:noreply, assign(socket, :show_config_modal, true)}
  end

  @impl true
  def handle_event("hide_config_modal", _params, socket) do
    {:noreply, assign(socket, :show_config_modal, false)}
  end

  @impl true
  def handle_event("toggle_scenario", %{"scenario" => scenario}, socket) do
    scenario_atom = String.to_atom(scenario)
    current_scenarios = socket.assigns.selected_scenarios

    updated_scenarios =
      if scenario_atom in current_scenarios do
        List.delete(current_scenarios, scenario_atom)
      else
        [scenario_atom | current_scenarios]
      end

    {:noreply, assign(socket, :selected_scenarios, updated_scenarios)}
  end

  @impl true
  def handle_event("toggle_variant", %{"variant" => variant}, socket) do
    variant_atom = String.to_atom(variant)
    current_variants = socket.assigns.selected_variants

    updated_variants =
      if variant_atom in current_variants do
        List.delete(current_variants, variant_atom)
      else
        [variant_atom | current_variants]
      end

    {:noreply, assign(socket, :selected_variants, updated_variants)}
  end

  @impl true
  def handle_event("update_config", params, socket) do
    config = %{
      parallel_tests: String.to_integer(params["parallel_tests"]),
      timeout_minutes: String.to_integer(params["timeout_minutes"]),
      significance_threshold: String.to_float(params["significance_threshold"])
    }

    {:noreply, assign(socket, :test_config, config)}
  end

  @impl true
  def handle_event("start_comparison", _params, socket) do
    %{
      selected_scenarios: scenarios,
      selected_variants: variants,
      test_config: config,
      current_user: user,
      current_scope: scope
    } = socket.assigns

    if length(scenarios) > 0 && length(variants) > 0 do
      # Generate agent variants
      agent_variants = Enum.map(variants, &AgentVariantGenerator.generate_variant/1)

      # Start comparison
      case LSPComparator.start_comparison(scenarios, agent_variants,
             parallel_tests: config.parallel_tests,
             timeout_minutes: config.timeout_minutes,
             significance_threshold: config.significance_threshold,
             user_id: user.id,
             organization_id: scope.id
           ) do
        {:ok, %{session_id: session_id}} ->
          # Subscribe to this session's updates
          PubSub.subscribe(Lang.PubSub, "lsp_comparison:#{session_id}")

          socket =
            socket
            |> assign(:current_session, session_id)
            |> assign(:show_config_modal, false)
            |> put_flash(:info, "LSP comparison test started successfully!")
            |> load_recent_sessions()

          {:noreply, socket}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start comparison: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select at least one scenario and one variant")}
    end
  end

  @impl true
  def handle_event("view_results", %{"session_id" => session_id}, socket) do
    case LSPComparator.get_results(session_id) do
      {:ok, results} ->
        analysis =
          PerformanceAnalyzer.analyze_comparison_results(results.lsp_enabled_results || %{})

        socket =
          socket
          |> assign(:results_data, results)
          |> assign(:analysis_data, analysis)
          |> assign(:show_results_modal, true)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to load results: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("hide_results_modal", _params, socket) do
    {:noreply, assign(socket, :show_results_modal, false)}
  end

  @impl true
  def handle_event("stop_session", %{"session_id" => session_id}, socket) do
    case LSPComparator.stop_comparison(session_id) do
      :ok ->
        socket =
          socket
          |> assign(:current_session, nil)
          |> put_flash(:info, "Test session stopped")
          |> load_recent_sessions()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop session: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("refresh_sessions", _params, socket) do
    {:noreply, load_recent_sessions(socket)}
  end

  @impl true
  def handle_info({:test_started, %{session_id: session_id}}, socket) do
    if session_id == socket.assigns.current_session do
      {:noreply, put_flash(socket, :info, "Test execution started")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:test_progress, %{completed: completed, total: total, session_id: session_id}},
        socket
      ) do
    if session_id == socket.assigns.current_session do
      progress_msg =
        "Progress: #{completed}/#{total} tests completed (#{round(completed / total * 100)}%)"

      {:noreply, put_flash(socket, :info, progress_msg)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:test_completed, %{session_id: session_id, results: results}}, socket) do
    if session_id == socket.assigns.current_session do
      socket =
        socket
        |> assign(:current_session, nil)
        |> put_flash(:info, "Test session completed! Click 'View Results' to see analysis.")
        |> load_recent_sessions()

      {:noreply, socket}
    else
      {:noreply, load_recent_sessions(socket)}
    end
  end

  # Private Functions

  defp load_recent_sessions(socket) do
    # In a real implementation, would load from database
    # For now, return empty list
    assign(socket, :test_sessions, [])
  end

  defp scenario_display_name(scenario_id) do
    case scenario_id do
      :legacy_modernization ->
        "Legacy Modernization"

      :dependency_hell ->
        "Dependency Hell Resolution"

      :performance_hunt ->
        "Performance Bottleneck Hunt"

      :security_audit ->
        "Security Vulnerability Audit"

      :test_coverage_gaps ->
        "Test Coverage Analysis"

      :api_evolution ->
        "API Contract Evolution"

      :error_propagation ->
        "Error Propagation Debugging"

      :style_harmonization ->
        "Code Style Harmonization"

      :domain_documentation ->
        "Domain Documentation"

      :collaborative_refactoring ->
        "Collaborative Refactoring"

      _ ->
        to_string(scenario_id)
        |> String.replace("_", " ")
        |> String.split()
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
    end
  end

  defp variant_display_name(variant_id) do
    case variant_id do
      :conservative_refactorer ->
        "Conservative Refactorer"

      :aggressive_optimizer ->
        "Aggressive Optimizer"

      :security_first_analyst ->
        "Security-First Analyst"

      :documentation_zealot ->
        "Documentation Zealot"

      :test_driven_purist ->
        "Test-Driven Purist"

      :pragmatic_balancer ->
        "Pragmatic Balancer"

      :speed_demon ->
        "Speed Demon"

      :academic_perfectionist ->
        "Academic Perfectionist"

      :enterprise_maintainer ->
        "Enterprise Maintainer"

      :startup_hacker ->
        "Startup Hacker"

      :claude_analytical_assistant ->
        "Claude Analytical Assistant"

      _ ->
        to_string(variant_id)
        |> String.replace("_", " ")
        |> String.split()
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
    end
  end

  defp format_duration(seconds) when is_number(seconds) do
    cond do
      seconds < 60 -> "#{round(seconds)}s"
      seconds < 3600 -> "#{round(seconds / 60)}m #{round(rem(round(seconds), 60))}s"
      true -> "#{round(seconds / 3600)}h #{round(rem(round(seconds), 3600) / 60)}m"
    end
  end

  defp format_duration(_), do: "Unknown"

  defp format_percentage(value) when is_number(value) do
    "#{Float.round(value, 1)}%"
  end

  defp format_percentage(_), do: "N/A"

  defp get_scenario_complexity(scenario_id) do
    case scenario_id do
      :legacy_modernization -> 5
      :dependency_hell -> 5
      :performance_hunt -> 4
      :security_audit -> 5
      :test_coverage_gaps -> 4
      :api_evolution -> 4
      :error_propagation -> 5
      :style_harmonization -> 3
      :domain_documentation -> 4
      :collaborative_refactoring -> 5
      _ -> 3
    end
  end

  defp get_variant_focus(variant_id) do
    case variant_id do
      :conservative_refactorer -> "Safety & Stability"
      :aggressive_optimizer -> "Performance"
      :security_first_analyst -> "Security"
      :documentation_zealot -> "Documentation"
      :test_driven_purist -> "Testing"
      :pragmatic_balancer -> "Balance"
      :speed_demon -> "Speed"
      :academic_perfectionist -> "Perfection"
      :enterprise_maintainer -> "Maintainability"
      :startup_hacker -> "Velocity"
      :claude_analytical_assistant -> "Analysis & Security"
      _ -> "General"
    end
  end

  defp estimate_test_duration(scenarios, variants, config) do
    total_tests = length(scenarios) * length(variants) * 2
    # Estimated average time per test
    avg_test_time_minutes = 5
    parallel_factor = config.parallel_tests

    estimated_minutes = total_tests * avg_test_time_minutes / parallel_factor

    cond do
      estimated_minutes < 60 -> "~#{round(estimated_minutes)} minutes"
      estimated_minutes < 1440 -> "~#{Float.round(estimated_minutes / 60, 1)} hours"
      true -> "~#{Float.round(estimated_minutes / 1440, 1)} days"
    end
  end
end
