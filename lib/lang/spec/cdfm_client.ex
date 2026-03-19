defmodule Lang.Spec.CDFMClient do
  @moduledoc """
  Minimal client for the CDFM Spec API using Req.

  This supports JSON uploads for messages with optional embedded attachments
  content. When attachments are present, they are sent as a base64 map under
  `attachments_content` keyed by the relative attachment path; the server is
  expected to persist the files alongside the message.

  Endpoints (expected):
  - POST /api/spec/requests/:id/messages
    Body: %{message: <map>, attachments_content: %{rel_path => base64}}
  - GET  /api/spec/requests/:id/messages?since=<iso8601>
    Response: [%{..., attachments_content: %{...}}]
  - POST /api/spec/requests/:id/status
    Body: %{status: "..."}
  """

  @type base_url :: String.t()
  @type token :: String.t() | nil

  defp default_headers(nil), do: []
  defp default_headers(token), do: [{"authorization", "Bearer " <> token}]

  def post_message(base_url, token, workspace_id, id, message_map, attachments_content \\ %{}) do
    url = build_url(base_url, workspace_id, "/requests/#{id}/messages")

    body = %{
      message: message_map,
      attachments_content: attachments_content
    }

    req()
    |> Req.post!(url: url, json: body, headers: default_headers(token))
    |> ok_body()
  end

  def fetch_messages(base_url, token, workspace_id, id, since_iso8601 \\ nil) do
    url = build_url(base_url, workspace_id, "/requests/#{id}/messages")
    params = if since_iso8601, do: [since: since_iso8601], else: []

    req()
    |> Req.get!(url: url, params: params, headers: default_headers(token))
    |> ok_body()
  end

  def set_status(base_url, token, workspace_id, id, status) do
    url = build_url(base_url, workspace_id, "/requests/#{id}/status")
    body = %{status: status}

    req()
    |> Req.post!(url: url, json: body, headers: default_headers(token))
    |> ok_body()
  end

  def fetch_export_jsonld(base_url, token, workspace_id, id) do
    url = build_url(base_url, workspace_id, "/requests/#{id}/export.jsonld")
    req()
    |> Req.get!(url: url, headers: default_headers(token))
    |> ok_body()
  end

  defp req do
    Req.new()
  end

  defp ok_body(%{status: status, body: body}) when status in 200..299, do: body
  defp ok_body(%{status: status, body: body}) do
    raise "CDFM API error: status=#{inspect(status)} body=#{inspect(body)}"
  end

  # Build a URL supporting both legacy and workspace-scoped paths.
  defp build_url(base_url, nil, suffix), do: Path.join(base_url, "/api/spec" <> suffix)
  defp build_url(base_url, workspace_id, suffix),
    do: Path.join(base_url, "/api/v1/workspaces/#{workspace_id}/spec" <> suffix)
end
