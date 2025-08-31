defmodule Lang.Security.SessionPolicy do
  @moduledoc """
  Policy gate for Markdown-LD session connects.

  Enforces static rules, plan/usage limits, host/path allowlists, and optionally
  delegates to the Core Explanation Engine for a justification verdict.
  """

  require Logger

  @type attrs :: %{
          optional(String.t()) => any(),
          optional(atom()) => any()
        }

  @spec authorize_connect(user :: map(), org :: map(), attrs :: attrs(), opts :: keyword()) ::
          {:ok, :allowed, map()} | {:error, atom(), map()}
  def authorize_connect(user, org, attrs, opts \\ []) when is_map(attrs) do
    with :ok <- check_ld_policy(attrs),
         :ok <- check_proto_requirements(attrs),
         :ok <- check_allowlists(attrs),
         {true, usage} <- billing_ok?(org),
         :ok <- explanation_gate(user, org, attrs) do
      {:ok, :allowed, %{usage: usage}}
    else
      {:error, reason} -> {:error, reason, %{}}
      {false, details} -> {:error, :plan_limit, details}
      other -> {:error, :unauthorized, %{details: other}}
    end
  end

  defp check_ld_policy(attrs) do
    case get(attrs, ["lds:policy", :policy]) do
      p when p in ["attach", "trusted"] -> :ok
      _ -> {:error, :policy_denied}
    end
  end

  defp check_proto_requirements(%{"lds:proto" => "ssh"} = a), do: check_proto_requirements(Map.put(a, :proto, "ssh"))
  defp check_proto_requirements(%{proto: "ssh"} = a) do
    case get(a, ["lds:fingerprint", :fingerprint]) do
      f when is_binary(f) ->
        if byte_size(String.trim(f)) > 0 do
          :ok
        else
          {:error, :missing_fingerprint}
        end
      _ ->
        {:error, :missing_fingerprint}
    end
  end

  defp check_proto_requirements(%{"lds:proto" => "unix"}), do: :ok
  defp check_proto_requirements(%{proto: "unix"}), do: :ok
  defp check_proto_requirements(%{"lds:proto" => "ws"}), do: :ok
  defp check_proto_requirements(%{proto: "ws"}), do: :ok
  defp check_proto_requirements(_), do: {:error, :unsupported_proto}

  defp check_allowlists(attrs) do
    case get(attrs, ["lds:proto", :proto]) do
      "ssh" ->
        host = get(attrs, ["lds:host", :host])
        allow = Application.get_env(:lang, :session_host_allowlist, [])
        if allow == [] or (is_binary(host) and Enum.any?(allow, &host_allowed?(host, &1))) do
          :ok
        else
          {:error, :host_not_allowed}
        end

      "unix" ->
        path = get(attrs, ["lds:path", :path])
        allow = Application.get_env(:lang, :session_unix_allowlist, [])
        if allow == [] or (is_binary(path) and Enum.any?(allow, &String.starts_with?(path, &1))) do
          :ok
        else
          {:error, :path_not_allowed}
        end

      "ws" ->
        url = get(attrs, ["lds:url", :url])
        allow_hosts = Application.get_env(:lang, :session_ws_host_allowlist, [])
        if allow_hosts == [] do
          :ok
        else
          with {:ok, %URI{host: h}} <- parse_uri(url),
               true <- Enum.any?(allow_hosts, &host_allowed?(h, &1)) do
            :ok
          else
            _ -> {:error, :ws_host_not_allowed}
          end
        end

      _ -> :ok
    end
  end

  defp billing_ok?(%{id: org_id}) do
    case Lang.Billing.Service.can_make_request?(org_id) do
      {true, usage} -> {true, usage}
      {false, details} -> {false, details}
    end
  end

  defp explanation_gate(user, org, attrs) do
    cfg = Application.get_env(:lang, :explain_gate, enabled: false, min_score: 0.85)
    if Keyword.get(cfg, :enabled, false) do
      min = Keyword.get(cfg, :min_score, 0.85)
      case Lang.Explanations.Core.evaluate_connect(user, org, attrs) do
        {:ok, %{verdict: :allow, score: s}} when is_number(s) and s >= min -> :ok
        {:ok, %{verdict: v, score: s}} -> {:error, {:explain_denied, %{verdict: v, score: s}}}
        {:error, reason} -> {:error, {:explain_error, reason}}
      end
    else
      :ok
    end
  end

  defp get(map, [a, b]) when is_map(map), do: Map.get(map, a) || Map.get(map, b)
  defp parse_uri(url) when is_binary(url) do
    try do
      {:ok, URI.parse(url)}
    rescue
      _ -> {:error, :invalid_url}
    end
  end
  defp parse_uri(_), do: {:error, :invalid_url}

  defp host_allowed?(host, pattern) do
    String.downcase(host) == String.downcase(pattern) or String.ends_with?(host, "." <> pattern)
  end
end
