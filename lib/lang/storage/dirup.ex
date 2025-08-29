defmodule Lang.Storage.Dirup do
  @moduledoc """
  Lightweight client for the Dirup storage service.

  Notes
  - Uses Req for HTTP per project guidelines.
  - Endpoints are inferred; adjust with env overrides if Dirup differs.
  - Keep calls short-lived; queue long jobs in Oban upstream if needed.
  """

  require Logger

  @default_timeout 5_000

  defp base_url do
    System.get_env("DIRUP_URL") || System.get_env("LANG_DIRUP_URL") || "http://127.0.0.1:7070"
  end

  defp token do
    System.get_env("DIRUP_TOKEN") || System.get_env("LANG_DIRUP_TOKEN")
  end

  defp req(opts \\ []) do
    headers =
      if t = token() do
        [{"authorization", "Bearer #{t}"}]
      else
        []
      end

    Req.new()
    |> Req.merge(base_url: base_url())
    |> Req.merge(put_headers: headers)
    |> Req.merge(receive_timeout: Keyword.get(opts, :timeout, @default_timeout))
  end

  def get_status do
    with {:ok, resp} <- Req.get(req(), url: "/status") do
      {:ok, safe_body(resp.body)}
    else
      {:error, e} -> {:error, {:http_error, e}}
    end
  end

  def validate_auth do
    # Fallback to status if no explicit endpoint
    case Req.get(req(), url: "/auth/validate") do
      {:ok, %{status: 200, body: body}} -> {:ok, safe_body(body)}
      {:ok, %{status: 404}} -> get_status()
      {:ok, other} -> {:error, {:invalid_status, other.status}}
      {:error, e} -> {:error, {:http_error, e}}
    end
  end

  def create_scratch(attrs) when is_map(attrs) do
    Req.post(req(), url: "/scratch", json: attrs)
    |> to_result()
  end

  def get_scratch(id) when is_binary(id) do
    Req.get(req(), url: "/scratch/#{URI.encode(id)}")
    |> to_result()
  end

  def update_scratch(id, attrs) when is_binary(id) and is_map(attrs) do
    Req.put(req(), url: "/scratch/#{URI.encode(id)}", json: attrs)
    |> to_result()
  end

  def cleanup_scratch(opts \\ %{}) when is_map(opts) do
    # Accept ttl_minutes or older_than
    Req.post(req(), url: "/scratch/cleanup", json: opts)
    |> to_result()
  end

  def get_project_context(project_id) when is_binary(project_id) do
    Req.get(req(), url: "/projects/#{URI.encode(project_id)}/context")
    |> to_result()
  end

  # ---------------------------------------------------------------------------
  # Patterns API
  # ---------------------------------------------------------------------------
  @doc """
  Store patterns in Dirup.
  Accepts a list of pattern maps. Returns stored IDs or details.
  """
  def store_patterns(patterns) when is_list(patterns) do
    Req.post(req(), url: "/patterns", json: %{patterns: patterns})
    |> to_result()
  end

  @doc """
  Retrieve patterns by IDs from Dirup.
  """
  def get_patterns(ids) when is_list(ids) do
    Req.post(req(), url: "/patterns/get", json: %{pattern_ids: ids})
    |> to_result()
  end

  @doc """
  Update a pattern confidence score.
  """
  def update_pattern_confidence(id, confidence) when is_binary(id) do
    Req.post(req(),
      url: "/patterns/#{URI.encode(id)}/confidence",
      json: %{confidence: confidence}
    )
    |> to_result()
  end

  # ---------------------------------------------------------------------------
  # User Context API
  # ---------------------------------------------------------------------------
  @doc """
  Update user context document in Dirup.
  """
  def update_user_context(user_id, context) when is_binary(user_id) and is_map(context) do
    Req.put(req(), url: "/users/#{URI.encode(user_id)}/context", json: context)
    |> to_result()
  end

  @doc """
  Get user context from Dirup.
  """
  def get_user_context(user_id) when is_binary(user_id) do
    Req.get(req(), url: "/users/#{URI.encode(user_id)}/context")
    |> to_result()
  end

  def create_session(attrs) when is_map(attrs) do
    Req.post(req(), url: "/sessions", json: attrs) |> to_result()
  end

  def get_session(id) when is_binary(id) do
    Req.get(req(), url: "/sessions/#{URI.encode(id)}") |> to_result()
  end

  def close_session(id) when is_binary(id) do
    Req.post(req(), url: "/sessions/#{URI.encode(id)}/close") |> to_result()
  end

  def sync_session(id, payload) when is_binary(id) and is_map(payload) do
    Req.post(req(), url: "/sessions/#{URI.encode(id)}/sync", json: payload) |> to_result()
  end

  defp to_result({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, safe_body(body)}
  end

  defp to_result({:ok, %{status: status, body: body}}) do
    {:error, {:http_status, status, body}}
  end

  defp to_result({:error, e}), do: {:error, {:http_error, e}}

  defp safe_body(%{} = body), do: body
  defp safe_body(list) when is_list(list), do: list
  defp safe_body(other), do: %{"data" => other}
end
