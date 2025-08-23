defmodule LangWeb.Api.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use LangWeb, :controller

  # This clause handles errors returned by Ecto's insert/update/delete.
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: LangWeb.Api.AnalysisView)
    |> render("errors.json", changeset: changeset)
  end

  # This clause is an example of how to handle resources that cannot be found.
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: LangWeb.ErrorView)
    |> render(:"404")
  end

  alias LangWeb.ApiError

  # Handle unauthorized access
  def call(conn, {:error, :unauthorized}) do
    ApiError.json(conn, :unauthorized, "Unauthorized")
  end

  # Handle forbidden access
  def call(conn, {:error, :forbidden}) do
    ApiError.json(conn, :forbidden, "Forbidden")
  end

  # Handle bad request errors
  def call(conn, {:error, :bad_request, message}) when is_binary(message) do
    ApiError.json(conn, :bad_request, message)
  end

  def call(conn, {:error, :bad_request}) do
    ApiError.json(conn, :bad_request, "Bad request")
  end

  # Handle unprocessable entity with custom message
  def call(conn, {:error, :unprocessable_entity, message}) when is_binary(message) do
    ApiError.json(conn, :unprocessable_entity, message)
  end

  # Handle rate limiting
  def call(conn, {:error, :rate_limited}) do
    ApiError.json(conn, :too_many_requests, "Rate limit exceeded")
  end

  # Handle service unavailable
  def call(conn, {:error, :service_unavailable}) do
    ApiError.json(conn, :service_unavailable, "Service temporarily unavailable")
  end

  # Handle timeout errors
  def call(conn, {:error, :timeout}) do
    ApiError.json(conn, :request_timeout, "Request timeout")
  end

  # Handle validation errors with custom messages
  def call(conn, {:error, :validation_failed, errors}) when is_map(errors) do
    # Keep structured validation errors shape
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  # Handle file upload errors
  def call(conn, {:error, :file_too_large}) do
    ApiError.json(conn, :request_entity_too_large, "File size exceeds maximum allowed")
  end

  def call(conn, {:error, :invalid_file_type}) do
    ApiError.json(conn, :unprocessable_entity, "Invalid file type")
  end

  # Handle analysis errors
  def call(conn, {:error, :analysis_failed, reason}) when is_binary(reason) do
    # Preserve extra reason field for debugging
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Analysis failed", reason: reason})
  end

  def call(conn, {:error, :analysis_failed}) do
    ApiError.json(conn, :unprocessable_entity, "Analysis failed")
  end

  # Handle quota exceeded
  def call(conn, {:error, :quota_exceeded}) do
    ApiError.json(conn, :payment_required, "Usage quota exceeded")
  end

  # Handle subscription required
  def call(conn, {:error, :subscription_required}) do
    ApiError.json(conn, :payment_required, "Active subscription required")
  end

  # Handle generic string errors
  def call(conn, {:error, message}) when is_binary(message) do
    ApiError.json(conn, :unprocessable_entity, message)
  end

  # Handle generic atom errors
  def call(conn, {:error, error_atom}) when is_atom(error_atom) do
    message = error_atom |> to_string() |> String.replace("_", " ") |> String.capitalize()
    ApiError.json(conn, :unprocessable_entity, message)
  end

  # Catch-all for unexpected errors
  def call(conn, error) do
    require Logger
    Logger.error("Unhandled fallback error: #{inspect(error)}")
    ApiError.json(conn, :internal_server_error, "Internal server error")
  end
end
