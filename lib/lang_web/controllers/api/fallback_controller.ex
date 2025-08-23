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

  # Handle unauthorized access
  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Unauthorized"})
  end

  # Handle forbidden access
  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Forbidden"})
  end

  # Handle bad request errors
  def call(conn, {:error, :bad_request, message}) when is_binary(message) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: message})
  end

  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Bad request"})
  end

  # Handle unprocessable entity with custom message
  def call(conn, {:error, :unprocessable_entity, message}) when is_binary(message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: message})
  end

  # Handle rate limiting
  def call(conn, {:error, :rate_limited}) do
    conn
    |> put_status(:too_many_requests)
    |> json(%{error: "Rate limit exceeded"})
  end

  # Handle service unavailable
  def call(conn, {:error, :service_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Service temporarily unavailable"})
  end

  # Handle timeout errors
  def call(conn, {:error, :timeout}) do
    conn
    |> put_status(:request_timeout)
    |> json(%{error: "Request timeout"})
  end

  # Handle validation errors with custom messages
  def call(conn, {:error, :validation_failed, errors}) when is_map(errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  # Handle file upload errors
  def call(conn, {:error, :file_too_large}) do
    conn
    |> put_status(:request_entity_too_large)
    |> json(%{error: "File size exceeds maximum allowed"})
  end

  def call(conn, {:error, :invalid_file_type}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invalid file type"})
  end

  # Handle analysis errors
  def call(conn, {:error, :analysis_failed, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Analysis failed", reason: reason})
  end

  def call(conn, {:error, :analysis_failed}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Analysis failed"})
  end

  # Handle quota exceeded
  def call(conn, {:error, :quota_exceeded}) do
    conn
    |> put_status(:payment_required)
    |> json(%{error: "Usage quota exceeded"})
  end

  # Handle subscription required
  def call(conn, {:error, :subscription_required}) do
    conn
    |> put_status(:payment_required)
    |> json(%{error: "Active subscription required"})
  end

  # Handle generic string errors
  def call(conn, {:error, message}) when is_binary(message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: message})
  end

  # Handle generic atom errors
  def call(conn, {:error, error_atom}) when is_atom(error_atom) do
    message = error_atom |> to_string() |> String.replace("_", " ") |> String.capitalize()

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: message})
  end

  # Catch-all for unexpected errors
  def call(conn, error) do
    require Logger
    Logger.error("Unhandled fallback error: #{inspect(error)}")

    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Internal server error"})
  end
end
