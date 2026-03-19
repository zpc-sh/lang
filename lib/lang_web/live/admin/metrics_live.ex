defmodule LangWeb.Admin.MetricsLive do
  @moduledoc """
  Real-time LSP Analytics Dashboard for monitoring token efficiency and productivity improvements.

  This LiveView provides comprehensive visualization of:
  - Token reduction metrics and trends
  - User productivity improvements
  - A/B testing results and statistical significance
  - Provider performance comparisons
  - Business impact calculations
  """

  use LangWeb, :live_view

  alias Lang.Analytics
  alias Lang.Analytics.LSPMetrics
  alias Lang.Metrics.TokenEfficiency
  alias Lang.Storage.MetricsStore
  alias Lang.Experiments.ABTesting

  # 30 seconds
  @update_interval 30_000
  @default_period_days 30

  def mount(_params, _session, socket) do
    # Subscribe to real-time analytics updates
    Phoenix.PubSub.subscribe(Lang.PubSub, "lsp_analytics:all")
    Phoenix.PubSub.subscribe(Lang.PubSub, "efficiency_reports:all")

    # Schedule periodic updates
    if connected?(socket) do
      :timer.send_interval(@update_interval, self(), :refresh_metrics)
    end

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:selected_period, @default_period_days)
      |> assign(:selected_organization, nil)
      |> assign(:dashboard_data, %{})
      |> assign(:time_series_data, [])
      |> assign(:ab_test_results, %{})
      |> assign(:provider_comparison, %{})
      |> assign(:business_metrics, %{})
      |> assign(:real_time_status, %{})
      |> load_dashboard_data()

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    period = String.to_integer(Map.get(params, "period", "#{@default_period_days}"))
    org_id = Map.get(params, "org_id")

    socket =
      socket
      |> assign(:selected_period, period)
      |> assign(:selected_organization, org_id)
      |> load_dashboard_data()

    {:noreply, socket}
  end

  def handle_event("change_period", %{"period" => period}, socket) do
    period_days = String.to_integer(period)

    socket =
      socket
      |> assign(:selected_period, period_days)
      |> push_patch(to: build_path(socket, period: period_days))

    {:noreply, socket}
  end

  def handle_event("change_organization", %{"organization_id" => org_id}, socket) do
    org_id = if org_id == "", do: nil, else: org_id

    socket =
      socket
      |> assign(:selected_organization, org_id)
      |> push_patch(to: build_path(socket, org_id: org_id))

    {:noreply, socket}
  end

  def handle_event("refresh_dashboard", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> load_dashboard_data()

    {:noreply, socket}
  end

  def handle_event("export_report", %{"format" => format}, socket) do
    case generate_business_report(socket) do
      {:ok, report_data} ->
        # In a real implementation, you'd generate and download the file
        socket =
          put_flash(socket, :info, "#{String.upcase(format)} report generated successfully")

        {:noreply, socket}

      {:error, _reason} ->
        socket = put_flash(socket, :error, "Failed to generate report")
        {:noreply, socket}
    end
  end

  def handle_info(:refresh_metrics, socket) do
    socket = load_dashboard_data(socket)
    {:noreply, socket}
  end

  def handle_info({:lsp_measurement_tracked, _event}, socket) do
    # Update real-time metrics when new events arrive
    socket = update_real_time_metrics(socket)
    {:noreply, socket}
  end

  def handle_info({:efficiency_report_generated, _report}, socket) do
    # Refresh dashboard when new efficiency reports are available
    socket = load_dashboard_data(socket)
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="min-h-screen bg-gray-50">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <!-- Header -->
          <div class="mb-8">
            <div class="sm:flex sm:items-center sm:justify-between">
              <div>
                <h1 class="text-3xl font-bold text-gray-900">LSP Analytics Dashboard</h1>
                <p class="mt-2 text-sm text-gray-600">
                  Real-time monitoring of token efficiency and productivity improvements
                </p>
              </div>
              <div class="mt-4 sm:mt-0 flex space-x-3">
                <.button
                  phx-click="refresh_dashboard"
                  class="bg-blue-600 hover:bg-blue-700"
                  disabled={@loading}
                >
                  <.icon name="hero-arrow-path" class="w-4 h-4 mr-2" />
                  {if @loading, do: "Loading...", else: "Refresh"}
                </.button>

                <.button
                  phx-click="export_report"
                  phx-value-format="pdf"
                  class="bg-green-600 hover:bg-green-700"
                >
                  <.icon name="hero-document-arrow-down" class="w-4 h-4 mr-2" /> Export Report
                </.button>
              </div>
            </div>
            
    <!-- Filters -->
            <div class="mt-6 flex flex-wrap gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Time Period</label>
                <select
                  phx-change="change_period"
                  name="period"
                  class="block w-32 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  value={@selected_period}
                >
                  <option value="1">Last 24h</option>
                  <option value="7">Last 7 days</option>
                  <option value="30">Last 30 days</option>
                  <option value="90">Last 90 days</option>
                </select>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Organization</label>
                <select
                  phx-change="change_organization"
                  name="organization_id"
                  class="block w-48 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                >
                  <option value="">All Organizations</option>
                  <!-- Organizations would be loaded dynamically -->
                </select>
              </div>
            </div>
          </div>

          <%= if @loading do %>
            <div class="flex items-center justify-center py-12">
              <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
              <span class="ml-3 text-gray-600">Loading analytics data...</span>
            </div>
          <% else %>
            <!-- Key Metrics Cards -->
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
              <.metric_card
                title="Token Reduction"
                value={"#{@dashboard_data.avg_token_reduction || 0}%"}
                change={calculate_change(@dashboard_data, :token_reduction)}
                trend={get_trend(@dashboard_data, :token_reduction)}
                icon="hero-chart-bar"
                color="blue"
              />

              <.metric_card
                title="Tokens Saved"
                value={format_number(@dashboard_data.total_tokens_saved || 0)}
                change={calculate_change(@dashboard_data, :tokens_saved)}
                trend={get_trend(@dashboard_data, :tokens_saved)}
                icon="hero-banknotes"
                color="green"
              />

              <.metric_card
                title="Time Saved"
                value={"#{@dashboard_data.avg_time_saved || 0}s"}
                change={calculate_change(@dashboard_data, :time_saved)}
                trend={get_trend(@dashboard_data, :time_saved)}
                icon="hero-clock"
                color="purple"
              />

              <.metric_card
                title="Operations"
                value={format_number(@dashboard_data.total_operations || 0)}
                change={calculate_change(@dashboard_data, :operations)}
                trend={get_trend(@dashboard_data, :operations)}
                icon="hero-cpu-chip"
                color="indigo"
              />
            </div>
            
    <!-- Charts and Analysis -->
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
              <!-- Token Efficiency Trend -->
              <div class="bg-white overflow-hidden shadow rounded-lg">
                <div class="p-5">
                  <div class="flex items-center">
                    <div class="flex-shrink-0">
                      <.icon name="hero-chart-line" class="h-6 w-6 text-blue-600" />
                    </div>
                    <div class="ml-3">
                      <h3 class="text-lg font-medium text-gray-900">Token Efficiency Trend</h3>
                      <p class="text-sm text-gray-500">Daily token reduction over time</p>
                    </div>
                  </div>

                  <div class="mt-5">
                    <%= if length(@time_series_data) > 0 do %>
                      <.efficiency_chart data={@time_series_data} />
                    <% else %>
                      <div class="text-center py-8 text-gray-500">
                        No data available for the selected period
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
              
    <!-- Provider Performance -->
              <div class="bg-white overflow-hidden shadow rounded-lg">
                <div class="p-5">
                  <div class="flex items-center">
                    <div class="flex-shrink-0">
                      <.icon name="hero-server-stack" class="h-6 w-6 text-green-600" />
                    </div>
                    <div class="ml-3">
                      <h3 class="text-lg font-medium text-gray-900">Provider Performance</h3>
                      <p class="text-sm text-gray-500">Efficiency by AI provider</p>
                    </div>
                  </div>

                  <div class="mt-5">
                    <.provider_comparison_table data={@provider_comparison} />
                  </div>
                </div>
              </div>
            </div>
            
    <!-- A/B Testing Results -->
            <%= if Map.get(@ab_test_results, :experiment_name) do %>
              <div class="bg-white overflow-hidden shadow rounded-lg mb-8">
                <div class="p-5">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center">
                      <div class="flex-shrink-0">
                        <.icon name="hero-beaker" class="h-6 w-6 text-purple-600" />
                      </div>
                      <div class="ml-3">
                        <h3 class="text-lg font-medium text-gray-900">A/B Testing Results</h3>
                        <p class="text-sm text-gray-500">Statistical significance analysis</p>
                      </div>
                    </div>

                    <div class="flex items-center space-x-2">
                      <span class={[
                        "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                        if(@ab_test_results.statistical_tests.overall_significance,
                          do: "bg-green-100 text-green-800",
                          else: "bg-yellow-100 text-yellow-800"
                        )
                      ]}>
                        {if @ab_test_results.statistical_tests.overall_significance,
                          do: "Statistically Significant",
                          else: "Not Yet Significant"}
                      </span>
                    </div>
                  </div>

                  <div class="mt-5">
                    <.ab_test_results_display results={@ab_test_results} />
                  </div>
                </div>
              </div>
            <% end %>
            
    <!-- Business Impact -->
            <div class="bg-white overflow-hidden shadow rounded-lg">
              <div class="p-5">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <.icon name="hero-currency-dollar" class="h-6 w-6 text-green-600" />
                  </div>
                  <div class="ml-3">
                    <h3 class="text-lg font-medium text-gray-900">Business Impact</h3>
                    <p class="text-sm text-gray-500">ROI and cost savings analysis</p>
                  </div>
                </div>

                <div class="mt-5">
                  <.business_impact_summary data={@business_metrics} />
                </div>
              </div>
            </div>
            
    <!-- Real-time Status -->
            <div class="mt-8 bg-blue-50 border border-blue-200 rounded-lg p-4">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <.icon name="hero-signal" class="h-5 w-5 text-blue-600" />
                </div>
                <div class="ml-3">
                  <p class="text-sm text-blue-800">
                    <strong>Live Status:</strong> Dashboard updates automatically every 30 seconds.
                    Last updated: {format_timestamp(DateTime.utc_now())}
                  </p>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Components

  defp metric_card(assigns) do
    ~H"""
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <.icon name={@icon} class={"h-6 w-6 text-#{@color}-600"} />
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">
                {@title}
              </dt>
              <dd class="flex items-baseline">
                <div class="text-2xl font-semibold text-gray-900">
                  {@value}
                </div>
                <%= if @change do %>
                  <div class={[
                    "ml-2 flex items-baseline text-sm font-semibold",
                    if(@trend == :up, do: "text-green-600", else: "text-red-600")
                  ]}>
                    <.icon
                      name={
                        if @trend == :up,
                          do: "hero-arrow-trending-up",
                          else: "hero-arrow-trending-down"
                      }
                      class="self-center flex-shrink-0 h-4 w-4"
                    />
                    {@change}%
                  </div>
                <% end %>
              </dd>
            </dl>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp efficiency_chart(assigns) do
    ~H"""
    <div class="h-64 w-full">
      <!-- In a real implementation, you'd use a charting library like Chart.js or D3 -->
      <div class="border border-gray-200 rounded h-full flex items-center justify-center">
        <div class="text-center">
          <.icon name="hero-chart-line" class="h-12 w-12 text-gray-400 mx-auto mb-2" />
          <p class="text-sm text-gray-500">Chart visualization would render here</p>
          <p class="text-xs text-gray-400 mt-1">
            {length(@data)} data points available
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp provider_comparison_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Provider
            </th>
            <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Operations
            </th>
            <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Avg. Reduction
            </th>
            <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Efficiency Grade
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <%= for {provider, metrics} <- @data do %>
            <tr>
              <td class="px-4 py-2 text-sm font-medium text-gray-900 capitalize">
                {provider}
              </td>
              <td class="px-4 py-2 text-sm text-gray-500">
                {format_number(metrics.operations)}
              </td>
              <td class="px-4 py-2 text-sm text-gray-500">
                {metrics.avg_token_reduction}%
              </td>
              <td class="px-4 py-2">
                <.efficiency_badge grade={metrics.efficiency_grade} />
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp ab_test_results_display(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
      <div>
        <h4 class="text-sm font-medium text-gray-900 mb-3">Treatment Group</h4>
        <dl class="space-y-2">
          <div class="flex justify-between">
            <dt class="text-sm text-gray-500">Sample Size:</dt>
            <dd class="text-sm font-medium text-gray-900">{@results.sample_sizes.treatment}</dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-sm text-gray-500">Avg. Token Reduction:</dt>
            <dd class="text-sm font-medium text-gray-900">
              {@results.treatment_group.avg_token_reduction}%
            </dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-sm text-gray-500">Avg. Time Saved:</dt>
            <dd class="text-sm font-medium text-gray-900">
              {@results.treatment_group.avg_time_saved}s
            </dd>
          </div>
        </dl>
      </div>

      <div>
        <h4 class="text-sm font-medium text-gray-900 mb-3">Control Group</h4>
        <dl class="space-y-2">
          <div class="flex justify-between">
            <dt class="text-sm text-gray-500">Sample Size:</dt>
            <dd class="text-sm font-medium text-gray-900">{@results.sample_sizes.control}</dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-sm text-gray-500">Avg. Token Reduction:</dt>
            <dd class="text-sm font-medium text-gray-900">
              {@results.control_group.avg_token_reduction}%
            </dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-sm text-gray-500">Avg. Time Saved:</dt>
            <dd class="text-sm font-medium text-gray-900">
              {@results.control_group.avg_time_saved}s
            </dd>
          </div>
        </dl>
      </div>
    </div>

    <div class="mt-6 p-4 bg-gray-50 rounded-lg">
      <h4 class="text-sm font-medium text-gray-900 mb-2">Key Findings</h4>
      <ul class="text-sm text-gray-600 space-y-1">
        <%= for finding <- Map.get(@results, :summary, %{}) |> Map.get(:key_findings, []) do %>
          <li class="flex items-start">
            <.icon name="hero-check-circle" class="h-4 w-4 text-green-500 mt-0.5 mr-2" />
            {finding}
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp business_impact_summary(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
      <div class="text-center">
        <div class="text-2xl font-bold text-green-600">
          ${format_currency(@data.monthly_cost_savings || 0)}
        </div>
        <div class="text-sm text-gray-500">Monthly Cost Savings</div>
      </div>

      <div class="text-center">
        <div class="text-2xl font-bold text-blue-600">
          ${format_currency(@data.productivity_value || 0)}
        </div>
        <div class="text-sm text-gray-500">Productivity Value</div>
      </div>

      <div class="text-center">
        <div class="text-2xl font-bold text-purple-600">
          {@data.roi_multiplier || 0}x
        </div>
        <div class="text-sm text-gray-500">ROI Multiplier</div>
      </div>
    </div>
    """
  end

  defp efficiency_badge(assigns) do
    color_class =
      case assigns.grade do
        grade when grade in ["A+", "A"] -> "bg-green-100 text-green-800"
        grade when grade in ["B+", "B"] -> "bg-blue-100 text-blue-800"
        grade when grade in ["C+", "C"] -> "bg-yellow-100 text-yellow-800"
        _ -> "bg-red-100 text-red-800"
      end

    assigns = assign(assigns, :color_class, color_class)

    ~H"""
    <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{@color_class}"}>
      {@grade}
    </span>
    """
  end

  # Helper functions

  defp load_dashboard_data(socket) do
    from = DateTime.add(DateTime.utc_now(), -socket.assigns.selected_period, :day)
    to = DateTime.utc_now()
    org_id = socket.assigns.selected_organization

    opts = [from: from, to: to]
    opts = if org_id, do: Keyword.put(opts, :organization_id, org_id), else: opts

    # Load dashboard summary
    dashboard_data =
      case MetricsStore.get_dashboard_summary(opts) do
        {:ok, data} -> data
        {:error, _} -> %{}
      end

    # Load time series data
    time_series_data =
      case MetricsStore.get_time_series_data(opts ++ [granularity: :daily]) do
        {:ok, data} -> data
        {:error, _} -> []
      end

    # Load A/B test results
    ab_test_results =
      case ABTesting.get_experiment_results("lsp_enhancements", opts) do
        {:ok, results} -> results
        {:error, _} -> %{}
      end

    # Load provider comparison
    provider_comparison =
      case TokenEfficiency.compare_provider_efficiency(opts) do
        {:ok, %{providers: providers}} -> providers
        {:error, _} -> %{}
      end

    # Calculate business metrics
    business_metrics = calculate_business_metrics(dashboard_data)

    socket
    |> assign(:loading, false)
    |> assign(:dashboard_data, dashboard_data)
    |> assign(:time_series_data, time_series_data)
    |> assign(:ab_test_results, ab_test_results)
    |> assign(:provider_comparison, provider_comparison)
    |> assign(:business_metrics, business_metrics)
  end

  defp update_real_time_metrics(socket) do
    case TokenEfficiency.get_realtime_efficiency() do
      {:ok, real_time_data} ->
        assign(socket, :real_time_status, real_time_data)

      {:error, _} ->
        socket
    end
  end

  defp calculate_business_metrics(dashboard_data) do
    tokens_saved = Map.get(dashboard_data, :total_tokens_saved, 0)
    time_saved = Map.get(dashboard_data, :avg_time_saved, 0)
    operations = Map.get(dashboard_data, :total_operations, 0)

    # Rough cost calculations
    cost_per_token = 0.00002
    developer_hourly_rate = 100

    monthly_cost_savings = tokens_saved * cost_per_token * 30
    productivity_value = time_saved * operations / 3600 * developer_hourly_rate

    # Monthly estimate
    infrastructure_cost = 500

    roi_multiplier =
      if infrastructure_cost > 0 do
        (monthly_cost_savings + productivity_value) / infrastructure_cost
      else
        0
      end

    %{
      monthly_cost_savings: monthly_cost_savings,
      productivity_value: productivity_value,
      roi_multiplier: Float.round(roi_multiplier, 1)
    }
  end

  defp generate_business_report(socket) do
    case Analytics.generate_business_report(
           from: DateTime.add(DateTime.utc_now(), -socket.assigns.selected_period, :day),
           to: DateTime.utc_now()
         ) do
      {:ok, report} -> {:ok, report}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_path(socket, opts) do
    base_path = ~p"/admin/metrics"

    query_params =
      opts
      |> Enum.filter(fn {_k, v} -> v != nil end)
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join("&")

    if query_params != "", do: "#{base_path}?#{query_params}", else: base_path
  end

  defp calculate_change(_data, _metric) do
    # In a real implementation, you'd compare with previous period
    nil
  end

  defp get_trend(_data, _metric) do
    # In a real implementation, you'd analyze trend direction
    :up
  end

  defp format_number(number) when is_integer(number) do
    Number.Delimit.number_to_delimited(number, precision: 0)
  end

  defp format_number(_), do: "0"

  defp format_currency(amount) when is_number(amount) do
    Number.Currency.number_to_currency(amount, precision: 0)
  end

  defp format_currency(_), do: "$0"

  defp format_timestamp(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
  end
end
