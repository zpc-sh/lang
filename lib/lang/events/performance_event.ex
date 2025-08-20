defmodule Lang.Events.PerformanceEvent do
  @moduledoc """
  Performance tracking events - temporarily disabled.
  """

  # Temporarily disabled due to missing AshEvent dependency
  # use AshEvent, domain: Lang.Events

  # Convenience functions for logging performance - temporarily disabled
  def log_response_time(_operation_type, _response_time_ms, _opts \\ []) do
    {:ok, :temporarily_disabled}
  end

  def log_memory_usage(_memory_mb, _context \\ %{}) do
    {:ok, :temporarily_disabled}
  end

  def log_db_query_time(_query_time_ms, _opts \\ []) do
    {:ok, :temporarily_disabled}
  end

  def log_queue_metrics(_queue_depth, _processing_time_ms, _opts \\ []) do
    {:ok, :temporarily_disabled}
  end

  # Query functions - temporarily disabled
  def get_operation_performance(_operation_type, _time_range \\ :hour) do
    {:ok, %{}}
  end

  def get_system_health_metrics(_time_range \\ :hour) do
    {:ok, %{}}
  end

  def get_slow_operations(_threshold_ms \\ 1000, _limit \\ 20) do
    {:ok, []}
  end
end
