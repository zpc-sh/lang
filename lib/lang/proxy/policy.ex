defmodule Lang.Proxy.Policy do
  @moduledoc """
  Simple, config-driven policy enforcement for proxy requests.

  This is a hard gate (deny by default for sensitive protocols). For richer,
  per-org policies, extend `resolve_policy/1` to consult Ash resources.

  Config examples:

      config :lang, :proxy_policy,
        allowed_protocols: [:ai, :lsp, :mcp],
        allow_ssh: false,
        allow_fs: false,
        allowed_hosts: []

      config :lang, :proxy_policies_by_org, %{
        "org-123" => [allow_ssh: true, allowed_hosts: ["10.0.0.9"]]
      }
  """

  @type env :: %{
          required(:service) => atom(),
          optional(:method) => String.t(),
          optional(:params) => map()
        }

  @doc """
  Authorizes a proxy request based on the configured policies.
  """
  @spec authorize(env(), map()) :: :ok | {:error, {:policy_denied, binary()}}
  def authorize(env, assigns) when is_map(env) and is_map(assigns) do
    org_id = assigns[:current_org] && assigns.current_org.id
    policy = resolve_policy(org_id)

    case env.service do
      :ai -> allow?(:ai, policy)
      :lsp -> authz_lsp(env, policy)
      :mcp -> allow?(:mcp, policy)
      :ssh -> authz_ssh(env, policy)
      :telnet -> authz_ssh(env, policy) # treat same as ssh but typically disabled
      :fs -> authz_fs(env, policy)
      _ -> {:error, {:policy_denied, "service not permitted"}}
    end
  end

  defp authz_lsp(%{method: method} = env, policy) do
    case to_string(method) do
      "lsp.bootstrap_ssh" -> authz_ssh(%{service: :ssh, params: env.params}, policy)
      _ -> allow?(:lsp, policy)
    end
  end

  defp authz_ssh(%{params: params}, policy) do
    cond do
      !Keyword.get(policy, :allow_ssh, false) -> {:error, {:policy_denied, "ssh disabled"}}
      is_list(policy[:allowed_hosts]) and policy[:allowed_hosts] != [] ->
        host = params && params["host"]
        if is_binary(host) and host in policy[:allowed_hosts] do
          :ok
        else
          {:error, {:policy_denied, "host not allowed"}}
        end

      true -> :ok
    end
  end

  defp authz_fs(_env, policy) do
    if Keyword.get(policy, :allow_fs, false), do: :ok, else: {:error, {:policy_denied, "fs disabled"}}
  end

  defp allow?(proto, policy) do
    allowed = Keyword.get(policy, :allowed_protocols, [:ai, :lsp, :mcp])
    if proto in allowed, do: :ok, else: {:error, {:policy_denied, "protocol not allowed"}}
  end

  defp resolve_policy(nil), do: base_policy()

  defp resolve_policy(org_id) do
    org_policies = Application.get_env(:lang, :proxy_policies_by_org, %{})
    org_policy = Map.get(org_policies, org_id, [])
    Keyword.merge(base_policy(), org_policy)
  end

  defp base_policy do
    Application.get_env(:lang, :proxy_policy, [])
  end
end

