defmodule Lang.APIUsage do
  @moduledoc """
  Unified API Usage interface that delegates to the appropriate backend.

  This module provides a consistent interface during the transition from
  the old APIUsage system to the new event-based system.

  Configuration:
    config :lang, :api_usage_backend, :events  # or :legacy
  """

  @default_backend :events

  def backend do
    Application.get_env(:lang, :api_usage_backend, @default_backend)
  end

  def log_usage(user_id, operation_type, opts \\ []) do
    backend_module().log_usage(user_id, operation_type, opts)
  end

  def log_analysis_usage(user_id, format, content_size, processing_time, opts \\ []) do
    backend_module().log_analysis_usage(user_id, format, content_size, processing_time, opts)
  end

  def log_lsp_usage(user_id, method, processing_time, opts \\ []) do
    backend_module().log_lsp_usage(user_id, method, processing_time, opts)
  end

  def log_conversation_usage(user_id, session_id, processing_time, opts \\ []) do
    backend_module().log_conversation_usage(user_id, session_id, processing_time, opts)
  end

  def log_timemachine_usage(user_id, timeline_id, processing_time, opts \\ []) do
    backend_module().log_timemachine_usage(user_id, timeline_id, processing_time, opts)
  end

  def log_error_usage(user_id, operation_type, error_type, opts \\ []) do
    backend_module().log_error_usage(user_id, operation_type, error_type, opts)
  end

  def log_rate_limited_usage(user_id, operation_type, opts \\ []) do
    backend_module().log_rate_limited_usage(user_id, operation_type, opts)
  end

  def current_month_count(user_id) do
    backend_module().current_month_count(user_id)
  end

  def is_over_limit?(user, operation_count \\ 1) do
    backend_module().is_over_limit?(user, operation_count)
  end

  def usage_percentage(user) do
    backend_module().usage_percentage(user)
  end

  def get_monthly_stats(user_id, month_year \\ nil) do
    backend_module().get_monthly_stats(user_id, month_year)
  end

  def subscribe_to_usage_updates(user_id) do
    backend_module().subscribe_to_usage_updates(user_id)
  end

  def subscribe_to_global_usage_updates() do
    backend_module().subscribe_to_global_usage_updates()
  end

  defp backend_module do
    case backend() do
      :legacy -> Lang.Accounts.APIUsageLogger
      :events -> Lang.Events.ApiUsageLogger
      _ -> Lang.Events.ApiUsageLogger
    end
  end
end
