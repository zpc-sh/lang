# LSP Analytics System - Integration Examples & Testing Guide

## Quick Start Integration

### 1. Provider Router Integration

Add analytics measurement to your existing LSP operations:

```elixir
# In lib/lang/providers/router.ex
def route_lsp_with_analytics(method, params, opts \\ []) do
  user_id = Keyword.get(opts, :user_id)
  organization_id = Keyword.get(opts, :organization_id)

  if user_id do
    # Use analytics wrapper for measurement
    Lang.Analytics.LSPMetrics.measure_lsp_operation(
      method: method,
      params: params,
      user_id: user_id,
      organization_id: organization_id,
      opts: opts
    )
  else
    # Standard LSP operation without analytics
    route_lsp(method, params, opts)
  end
end

# Example usage in your LSP handlers
def handle_completion(params, user_context) do
  route_lsp_with_analytics(
    :completion,
    params,
    user_id: user_context.user_id,
    organization_id: user_context.organization_id
  )
end
```

### 2. Manual Event Tracking

For operations not going through the provider router:

```elixir
# Track a manual measurement
Lang.Analytics.LSPMetrics.record_measurement(%{
  user_id: user.id,
  organization_id: user.organization_id,
  lsp_method: :hover,
  baseline_tokens: 120,
  enhanced_tokens: 85,
  time_saved_seconds: 15,
  quality_score: 0.88,
  language: "elixir",
  provider: "xai",
  metadata: %{
    file_type: "ex",
    context_size: "medium"
  }
})
```

### 3. A/B Testing Integration

Add A/B testing to your user authentication:

```elixir
# In your auth helpers
defmodule LangWeb.AuthHelpers do
  def current_user_with_experiments(conn) do
    user = current_user(conn)

    if user do
      # Assign user to LSP enhancement experiment
      {:ok, _cohort} = Lang.Analytics.assign_ab_cohort(user.id, "lsp_enhancements")
      user
    else
      nil
    end
  end

  def lsp_enhancements_enabled?(user_id) do
    Lang.Analytics.lsp_enhancement_enabled?(user_id)
  end
end
```

## Testing the Analytics System

### 1. Unit Tests

```elixir
# test/lang/analytics/lsp_metrics_test.exs
defmodule Lang.Analytics.LSPMetricsTest do
  use Lang.DataCase
  alias Lang.Analytics.LSPMetrics

  describe "measure_lsp_operation/1" do
    test "tracks token efficiency for completion operations" do
      user = create_user()

      # Mock LSP completion that saves tokens
      expect(Lang.Providers.Router, :route_lsp, fn :completion, _params, _opts ->
        {:ok, %{content: "def hello", usage: %{total_tokens: 95}}}
      end)

      result = LSPMetrics.measure_lsp_operation(
        method: :completion,
        params: %{context: "def ", language: "elixir"},
        user_id: user.id
      )

      assert {:ok, response} = result

      # Verify measurement was recorded
      events = Lang.Analytics.LSPMeasurementEvent.read_all!()
      assert length(events) == 1

      event = hd(events)
      assert event.user_id == user.id
      assert event.lsp_method == :completion
      assert event.enhanced_tokens == 95
      assert event.baseline_tokens > event.enhanced_tokens
    end
  end

  describe "A/B testing" do
    test "assigns users to consistent cohorts" do
      user = create_user()

      # First assignment
      {:ok, cohort1} = Lang.Analytics.assign_ab_cohort(user.id, "test_experiment")

      # Second assignment should be the same
      {:ok, cohort2} = Lang.Analytics.assign_ab_cohort(user.id, "test_experiment")

      assert cohort1.cohort_type == cohort2.cohort_type
      assert cohort1.id == cohort2.id
    end
  end
end
```

### 2. Integration Tests

```elixir
# test/lang_web/live/admin/metrics_live_test.exs
defmodule LangWeb.Admin.MetricsLiveTest do
  use LangWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "metrics dashboard" do
    test "displays analytics data", %{conn: conn} do
      user = create_admin_user()

      # Create some test measurement data
      create_measurement_events()

      {:ok, live, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/admin/metrics")

      assert html =~ "LSP Analytics Dashboard"
      assert html =~ "Token Reduction"
      assert has_element?(live, "[data-testid=token-reduction-metric]")
    end

    test "updates in real-time", %{conn: conn} do
      user = create_admin_user()

      {:ok, live, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/admin/metrics")

      # Simulate new measurement event
      Phoenix.PubSub.broadcast(
        Lang.PubSub,
        "lsp_analytics:all",
        {:lsp_measurement_tracked, create_measurement_event()}
      )

      # Dashboard should update
      assert_receive {:live_patch, _}
    end
  end
end
```

### 3. Load Testing

```elixir
# test/lang/analytics/performance_test.exs
defmodule Lang.Analytics.PerformanceTest do
  use Lang.DataCase

  @tag :performance
  test "handles high-volume measurement events" do
    user = create_user()

    # Generate 1000 concurrent measurements
    tasks = for i <- 1..1000 do
      Task.async(fn ->
        Lang.Analytics.track_lsp_event(%{
          user_id: user.id,
          lsp_method: :completion,
          baseline_tokens: 100 + i,
          enhanced_tokens: 80 + i,
          time_saved_seconds: 10,
          occurred_at: DateTime.utc_now()
        })
      end)
    end

    results = Task.await_many(tasks, 30_000)

    # All should succeed
    assert Enum.all?(results, &match?({:ok, _}, &1))

    # Verify all events were stored
    events = Lang.Analytics.LSPMeasurementEvent.read_all!()
    assert length(events) == 1000
  end
end
```

## Production Deployment

### 1. Environment Setup

```bash
# Production environment variables
export ANALYTICS_ENABLED=true
export ANALYTICS_RETENTION_DAYS=365
export ANALYTICS_BATCH_SIZE=1000
export AB_TESTING_ENABLED=true
export DASHBOARD_EXPORT_ENABLED=true
```

### 2. Oban Configuration

```elixir
# config/prod.exs
config :lang, Oban,
  repo: Lang.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # Daily efficiency reports
       {"0 1 * * *", Lang.Workers.ProductivityMetricsWorker,
        %{task: "generate_efficiency_report", period_type: "daily"}},

       # Weekly data cleanup
       {"0 2 * * 0", Lang.Workers.ProductivityMetricsWorker,
        %{task: "cleanup_old_data", retention_days: 365}},

       # Hourly user metrics updates
       {"0 * * * *", Lang.Workers.ProductivityMetricsWorker,
        %{task: "aggregate_organization_metrics", period_type: "hourly"}}
     ]}
  ],
  queues: [
    default: 10,
    analytics: 8,
    reports: 3,
    cleanup: 1
  ]
```

### 3. Database Indexes

```sql
-- Essential indexes for performance
CREATE INDEX CONCURRENTLY idx_lsp_measurement_events_user_occurred
ON lsp_measurement_events (user_id, occurred_at DESC);

CREATE INDEX CONCURRENTLY idx_lsp_measurement_events_org_occurred
ON lsp_measurement_events (organization_id, occurred_at DESC);

CREATE INDEX CONCURRENTLY idx_lsp_measurement_events_method_provider
ON lsp_measurement_events (lsp_method, provider);

CREATE INDEX CONCURRENTLY idx_user_productivity_metrics_period
ON user_productivity_metrics (user_id, period_start, period_end);

CREATE INDEX CONCURRENTLY idx_ab_test_cohorts_experiment
ON ab_test_cohorts (experiment_name, cohort_type, assigned_at);
```

## Monitoring & Observability

### 1. Custom Telemetry

```elixir
# lib/lang/analytics/telemetry.ex
defmodule Lang.Analytics.Telemetry do
  def setup do
    :telemetry.attach_many(
      "lang-analytics-telemetry",
      [
        [:lang, :analytics, :measurement, :start],
        [:lang, :analytics, :measurement, :stop],
        [:lang, :analytics, :measurement, :exception]
      ],
      &handle_event/4,
      %{}
    )
  end

  def handle_event([:lang, :analytics, :measurement, :start], _measurements, metadata, _config) do
    Logger.info("Analytics measurement started", metadata)
  end

  def handle_event([:lang, :analytics, :measurement, :stop], measurements, metadata, _config) do
    Logger.info("Analytics measurement completed",
      Map.merge(metadata, %{duration: measurements.duration}))
  end

  def handle_event([:lang, :analytics, :measurement, :exception], _measurements, metadata, _config) do
    Logger.error("Analytics measurement failed", metadata)
  end
end
```

### 2. Health Checks

```elixir
# lib/lang/analytics/health_check.ex
defmodule Lang.Analytics.HealthCheck do
  def system_health do
    %{
      analytics_enabled: analytics_enabled?(),
      recent_events: count_recent_events(),
      ab_tests_active: count_active_experiments(),
      storage_health: check_storage_health(),
      worker_health: check_worker_health(),
      timestamp: DateTime.utc_now()
    }
  end

  defp analytics_enabled? do
    Application.get_env(:lang, :analytics_enabled, false)
  end

  defp count_recent_events do
    from_time = DateTime.add(DateTime.utc_now(), -1, :hour)

    import Ash.Query

    Lang.Analytics.LSPMeasurementEvent
    |> Ash.Query.filter(occurred_at >= ^from_time)
    |> Ash.count!()
  end

  defp count_active_experiments do
    import Ash.Query

    Lang.Analytics.ABTestCohort
    |> Ash.Query.filter(experiment_status == :active)
    |> Ash.count!()
  end

  defp check_storage_health do
    try do
      case Ecto.Adapters.SQL.query(Lang.Repo, "SELECT 1", []) do
        {:ok, _} -> :healthy
        {:error, _} -> :unhealthy
      end
    rescue
      _ -> :unhealthy
    end
  end

  defp check_worker_health do
    case Oban.check_queue(Lang.Oban, queue: :analytics) do
      :ok -> :healthy
      _ -> :unhealthy
    end
  end
end
```

## Real-World Usage Examples

### 1. Customer Success Analysis

```elixir
# Generate customer success report
def generate_customer_success_report(organization_id) do
  with {:ok, analytics} <- Lang.Storage.MetricsStore.get_organization_analytics(organization_id),
       {:ok, efficiency} <- Lang.Metrics.TokenEfficiency.get_efficiency_trends(
         organization_id: organization_id
       ) do

    success_metrics = %{
      organization_id: organization_id,
      monthly_token_savings: calculate_monthly_savings(analytics),
      productivity_improvement: calculate_productivity_gain(analytics),
      user_satisfaction: calculate_satisfaction_score(analytics),
      roi_achieved: calculate_roi(analytics),
      trend_analysis: analyze_trends(efficiency)
    }

    {:ok, success_metrics}
  end
end
```

### 2. Performance Optimization

```elixir
# Identify optimization opportunities
def identify_optimization_opportunities(organization_id) do
  with {:ok, provider_comparison} <- Lang.Metrics.TokenEfficiency.compare_provider_efficiency(
         organization_id: organization_id
       ),
       {:ok, method_analysis} <- analyze_method_performance(organization_id) do

    opportunities = []

    # Check for underperforming providers
    opportunities = opportunities ++ check_provider_performance(provider_comparison)

    # Check for underperforming methods
    opportunities = opportunities ++ check_method_performance(method_analysis)

    # Check for user adoption issues
    opportunities = opportunities ++ check_adoption_issues(organization_id)

    {:ok, opportunities}
  end
end
```

### 3. Automated Alerting

```elixir
# lib/lang/analytics/alerts.ex
defmodule Lang.Analytics.Alerts do
  def check_performance_alerts(organization_id) do
    with {:ok, metrics} <- get_recent_metrics(organization_id) do
      alerts = []

      # Check for performance degradation
      if metrics.avg_token_reduction < 10.0 do
        alerts = alerts ++ [%{
          type: :performance_degradation,
          message: "Token reduction below threshold (#{metrics.avg_token_reduction}%)",
          severity: :warning,
          organization_id: organization_id
        }]
      end

      # Check for statistical significance
      case Lang.Experiments.ABTesting.test_statistical_significance("lsp_enhancements") do
        {:ok, %{is_statistically_significant: true}} ->
          alerts = alerts ++ [%{
            type: :experiment_significant,
            message: "A/B test results are now statistically significant",
            severity: :info,
            organization_id: organization_id
          }]
        _ -> alerts
      end

      {:ok, alerts}
    end
  end

  def send_alerts(alerts) do
    Enum.each(alerts, fn alert ->
      # Send to your notification system
      notify_stakeholders(alert)
    end)
  end
end
```

## Troubleshooting Guide

### Common Issues

1. **Missing Measurements**
   ```elixir
   # Check if analytics is enabled
   iex> Application.get_env(:lang, :analytics_enabled)
   true

   # Check recent events
   iex> Lang.Analytics.LSPMeasurementEvent.read_all!() |> length()
   150

   # Check user assignment
   iex> Lang.Analytics.lsp_enhancement_enabled?(user_id)
   true
   ```

2. **Dashboard Loading Issues**
   ```elixir
   # Clear metrics cache
   iex> :ets.delete_all_objects(:metrics_cache)

   # Check storage health
   iex> Lang.Analytics.HealthCheck.system_health()
   ```

3. **Background Jobs Not Processing**
   ```bash
   # Check Oban status
   mix oban.stats

   # Restart failed jobs
   mix oban.resume queue: analytics
   ```

## Performance Optimization

### 1. Database Tuning

```sql
-- Optimize measurement event queries
EXPLAIN ANALYZE SELECT * FROM lsp_measurement_events
WHERE user_id = ? AND occurred_at >= ?
ORDER BY occurred_at DESC LIMIT 100;

-- Create partial indexes for hot queries
CREATE INDEX idx_lsp_events_recent
ON lsp_measurement_events (user_id, occurred_at DESC)
WHERE occurred_at >= CURRENT_DATE - INTERVAL '30 days';
```

### 2. Caching Strategy

```elixir
# Implement smart caching for dashboard data
defmodule Lang.Analytics.Cache do
  @cache_ttl 300 # 5 minutes

  def get_dashboard_data(organization_id, opts) do
    cache_key = "dashboard:#{organization_id}:#{:crypto.hash(:md5, inspect(opts))}"

    case Cachex.get(:analytics_cache, cache_key) do
      {:ok, nil} ->
        # Cache miss - fetch and cache
        case fetch_dashboard_data(organization_id, opts) do
          {:ok, data} ->
            Cachex.put(:analytics_cache, cache_key, data, ttl: @cache_ttl)
            {:ok, data}
          error -> error
        end

      {:ok, data} ->
        # Cache hit
        {:ok, data}
    end
  end
end
```

### 3. Batch Processing

```elixir
# Process measurements in batches for better performance
def process_measurement_batch(events) when length(events) > 100 do
  events
  |> Enum.chunk_every(100)
  |> Enum.each(fn batch ->
    Lang.Storage.MetricsStore.bulk_store_measurement_events(batch)
  end)
end
```

This integration guide provides everything needed to successfully deploy and operate the LSP Analytics System in production, with comprehensive testing, monitoring, and optimization strategies.
