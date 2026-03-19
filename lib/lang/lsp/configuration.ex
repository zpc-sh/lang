defmodule Lang.LSP.Configuration do
  @moduledoc """
  Canonical, sanitized per-request configuration/context passed to LSP Domain Brokers.

  Sources:
  - WebSocket ticket claims (cid/org) injected in params by `Lang.LSP.Instance.inject_identity/2`
  - LSP initialize/configuration messages (e.g., workspace root)
  - Request params (fallbacks only)
  """

  @enforce_keys []
  defstruct [
    :client_id,
    :org_id,
    :workspace_root,
    :project_id,
    :session_id,
    :features,
    :limits,
    :repository
  ]

  @type t :: %__MODULE__{
          client_id: String.t() | nil,
          org_id: String.t() | nil,
          workspace_root: String.t() | nil,
          project_id: String.t() | nil,
          session_id: String.t() | nil,
          features: map() | nil,
          limits: map() | nil,
          repository: map() | nil
        }

  @doc """
  Build a Configuration from a JSON-RPC request map.

  Looks at params keys typically injected/used in our stack:
  - "current_cid" | "client_id"
  - "current_org" (expects %{id: ...}) | "organization_id" | "org_id"
  - "workspace_root" | "root" | "path" (last two as fallbacks)
  - "project_id"
  - "session_id"
  - "features" / "limits" (optional maps)
  """
  @spec from_request(map()) :: t()
  def from_request(%{"params" => params} = req) when is_map(params) do
    org_id =
      case params["current_org"] do
        %{} = org -> org["id"] || org[:id]
        _ -> params["organization_id"] || params["org_id"]
      end

    %__MODULE__{
      client_id: params["current_cid"] || params["client_id"],
      org_id: org_id,
      workspace_root: derive_workspace_root(req, params),
      project_id: params["project_id"],
      session_id: params["session_id"],
      features: params["features"],
      limits: params["limits"],
      repository: derive_repository(params)
    }
  end

  def from_request(_), do: %__MODULE__{}

  defp derive_workspace_root(%{"method" => meth}, params) when is_binary(meth) do
    # Priority: explicit workspace_root, else rootUri/rootPath from initialize-like calls, else nil
    params["workspace_root"] ||
      normalize_root_uri(params["rootUri"]) ||
      normalize_root_path(params["rootPath"]) ||
      nil
  end
  defp derive_workspace_root(_, params), do: params["workspace_root"]

  defp normalize_root_uri("file://" <> rest) do
    Path.expand("/" <> String.trim_leading(rest, "/"))
  rescue
    _ -> nil
  end
  defp normalize_root_uri(_), do: nil

  defp normalize_root_path(path) when is_binary(path) do
    Path.expand(path)
  rescue
    _ -> nil
  end
  defp normalize_root_path(_), do: nil

  defp derive_repository(params) do
    org = params["org"] || params["organization"]
    user = params["user"] || params["owner"]
    ws = params["workspace"] || params["workspace_name"]
    if Enum.any?([org, user, ws], &is_binary/1) do
      %{"org" => org, "user" => user, "workspace" => ws}
    else
      nil
    end
  end
end
