defmodule LangWeb.Plugs.AuthAndRateLimit do
  @moduledoc """
  Plug for API authentication and rate limiting for LANG SaaS platform
  """

  import Plug.Conn

  import Plug.Conn,
    only: [put_status: 2, assign: 3, get_req_header: 2, put_resp_header: 3, halt: 1]

  import Phoenix.Controller, only: [json: 2]

  alias Lang.Accounts
  alias Lang.Accounts.{User, APIUsage}
  alias Lang.Security.RateLimiter

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    case authenticate_request(conn) do
      {:ok, user} ->
        conn
        |> assign(:current_user, user)
        |> check_rate_limit(user)
        |> log_request_start()

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or missing API key"})
        |> halt()

      {:error, :inactive_user} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Account is inactive"})
        |> halt()
    end
  end

  defp authenticate_request(conn) do
    with {:ok, api_key} <- extract_api_key(conn),
         {:ok, user} <- get_user_by_api_key(api_key),
         true <- user.is_active do
      {:ok, user}
    else
      false -> {:error, :inactive_user}
      _ -> {:error, :unauthorized}
    end
  end

  defp extract_api_key(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> api_key] ->
        {:ok, api_key}

      [api_key] ->
        {:ok, api_key}

      _ ->
        # Also check query params as fallback
        case conn.query_params["api_key"] do
          nil -> {:error, :no_api_key}
          key -> {:ok, key}
        end
    end
  end

  defp get_user_by_api_key(api_key) do
    case Accounts.User
         |> Ash.Query.filter(api_key: api_key)
         |> Ash.read_one() do
      {:ok, user} when not is_nil(user) -> {:ok, user}
      _ -> {:error, :user_not_found}
    end
  rescue
    _ -> {:error, :database_error}
  end

  defp check_rate_limit(conn, user) do
    operation = determine_operation(conn)
    identifier = "user_#{user.id}"

    case RateLimiter.check_rate_limit(identifier, operation) do
      :ok ->
        case APIUsage.is_over_limit?(user) do
          true ->
            log_rate_limited(conn, user, :monthly_limit)

            conn
            |> put_status(:too_many_requests)
            |> put_resp_header("x-ratelimit-limit", to_string(user.monthly_request_limit))
            |> put_resp_header("x-ratelimit-remaining", "0")
            |> put_resp_header("retry-after", "3600")
            |> json(%{
              error: "Monthly quota exceeded",
              limit: user.monthly_request_limit,
              current_usage: get_current_usage(user),
              reset_date: get_reset_date(user)
            })
            |> halt()

          false ->
            conn
            |> put_usage_headers(user)
        end

      {:error, :rate_limited} ->
        log_rate_limited(conn, user, :rate_limit)

        conn
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", "60")
        |> json(%{error: "Rate limit exceeded. Please slow down your requests."})
        |> halt()
    end
  end

  defp determine_operation(conn) do
    case conn.path_info do
      ["api", "analyze"] -> "analyze"
      ["api", "conversation" | _] -> "conversation"
      ["api", "stylometrics" | _] -> "stylometrics"
      ["api", "timemachine" | _] -> "timemachine"
      ["lsp" | _] -> "lsp"
      _ -> "default"
    end
  end

  defp put_usage_headers(conn, user) do
    case APIUsage.current_month_count(user.id) do
      {:ok, current_count} ->
        remaining = max(0, user.monthly_request_limit - current_count)

        conn
        |> put_resp_header("x-ratelimit-limit", to_string(user.monthly_request_limit))
        |> put_resp_header("x-ratelimit-remaining", to_string(remaining))
        |> put_resp_header("x-ratelimit-reset", get_reset_timestamp(user))

      _ ->
        conn
    end
  end

  defp log_request_start(conn) do
    start_time = System.monotonic_time(:millisecond)
    assign(conn, :request_start_time, start_time)
  end

  defp log_rate_limited(conn, user, reason) do
    APIUsage.log_usage(
      user_id: user.id,
      operation_type: determine_operation(conn) |> String.to_atom(),
      status: :rate_limited,
      error_type: to_string(reason),
      ip_address: get_client_ip(conn),
      user_agent: get_user_agent(conn),
      request_id: get_request_id(conn)
    )
  end

  defp get_current_usage(user) do
    case APIUsage.current_month_count(user.id) do
      {:ok, count} -> count
      _ -> 0
    end
  end

  defp get_reset_date(user) do
    next_month =
      user.last_request_reset
      |> DateTime.add(30, :day)
      |> DateTime.to_date()

    Date.to_iso8601(next_month)
  end

  defp get_reset_timestamp(user) do
    user.last_request_reset
    |> DateTime.add(30, :day)
    |> DateTime.to_unix()
    |> to_string()
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] ->
        ip

      [] ->
        case conn.remote_ip do
          {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
          _ -> "unknown"
        end
    end
  end

  defp get_user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [ua] -> ua
      [] -> "unknown"
    end
  end

  defp get_request_id(conn) do
    case get_req_header(conn, "x-request-id") do
      [id] ->
        id

      [] ->
        case conn.assigns[:request_id] do
          nil -> Ash.UUID.generate()
          id -> id
        end
    end
  end

  @doc """
  Helper to log successful API usage after request completion.
  Call this from your controllers after successful operations.
  """
  def log_successful_usage(conn, format \\ nil, content_size \\ nil) do
    if user = conn.assigns[:current_user] do
      processing_time =
        case conn.assigns[:request_start_time] do
          nil -> nil
          start_time -> System.monotonic_time(:millisecond) - start_time
        end

      APIUsage.log_usage(
        user_id: user.id,
        operation_type: determine_operation(conn) |> String.to_atom(),
        format: format,
        content_size_bytes: content_size,
        processing_time_ms: processing_time,
        status: :success,
        ip_address: get_client_ip(conn),
        user_agent: get_user_agent(conn),
        request_id: get_request_id(conn)
      )

      # Increment the user's request count
      User.increment_request_count(user)
    end

    conn
  end

  @doc """
  Helper to log failed API usage.
  Call this from error handlers.
  """
  def log_failed_usage(conn, error_type, format \\ nil, content_size \\ nil) do
    if user = conn.assigns[:current_user] do
      processing_time =
        case conn.assigns[:request_start_time] do
          nil -> nil
          start_time -> System.monotonic_time(:millisecond) - start_time
        end

      APIUsage.log_usage(
        user_id: user.id,
        operation_type: determine_operation(conn) |> String.to_atom(),
        format: format,
        content_size_bytes: content_size,
        processing_time_ms: processing_time,
        status: :error,
        error_type: to_string(error_type),
        ip_address: get_client_ip(conn),
        user_agent: get_user_agent(conn),
        request_id: get_request_id(conn)
      )
    end

    conn
  end
end
