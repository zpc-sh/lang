defmodule Lang.Events.ErrorEvent do
  @moduledoc """
  Event for error tracking and monitoring - temporarily disabled.
  """

  # Temporarily disabled due to missing AshEvent dependency
  # use AshEvent, domain: Lang.Events

  # Convenience functions for logging errors - temporarily disabled
  def log_error(_error_type, _message, _opts \\ []) do
    {:ok, :temporarily_disabled}
  end

  def log_exception(_exception, _stacktrace, _opts \\ []) do
    {:ok, :temporarily_disabled}
  end

  def log_http_error(_status, _path, _method, _opts \\ []) do
    {:ok, :temporarily_disabled}
  end

  def log_validation_error(_field, _message, _opts \\ []) do
    {:ok, :temporarily_disabled}
  end

  def log_rate_limit_error(_user_id, _operation_type, _opts \\ []) do
    {:ok, :temporarily_disabled}
  end

  def log_database_error(_error, _query, _opts \\ []) do
    {:ok, :temporarily_disabled}
  end

  def log_external_api_error(_service, _status, _response, _opts \\ []) do
    {:ok, :temporarily_disabled}
  end

  # Query functions - temporarily disabled
  def get_error_summary(_time_range \\ :hour) do
    {:ok, %{total_errors: 0}}
  end

  def get_error_breakdown_by_type(_time_range \\ :hour) do
    {:ok, []}
  end

  def get_user_errors(_user_id, _time_range \\ :day) do
    {:ok, []}
  end

  def get_critical_errors(_time_range \\ :hour) do
    {:ok, []}
  end

  def get_error_trend(_error_type, _time_range \\ :day) do
    {:ok, []}
  end

  def get_recovery_stats(_time_range \\ :day) do
    {:ok, %{}}
  end
end
