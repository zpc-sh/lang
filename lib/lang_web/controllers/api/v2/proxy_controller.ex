defmodule LangWeb.Api.V2.ProxyController do
  @moduledoc "Proxy API v2 Controller: routes proxy envelopes to services via primary proxy protocol."

  use LangWeb, :controller

  alias Lang.Proxy.{Envelope, Router}
  alias Lang.Billing.Service, as: BillingService
  require Logger

  action_fallback LangWeb.Api.FallbackController

  def call(conn, params) when is_map(params) do
    with %{current_org: org, current_user: user} <- conn.assigns,
         true <- not is_nil(org) or halt_unauthorized(conn),
         {true, bill} <- BillingService.can_make_request?(org.id),
         {:ok, env0} <- Envelope.new(params),
         env <- %Envelope{env0 | meta: conn.assigns},
         :ok <- maybe_validate_session(env),
         :ok <- maybe_authorize(env, conn.assigns),
         :ok <- maybe_require_intent(env, conn.assigns),
         :ok <- maybe_heuristics_precheck(env, conn.assigns) do
      case Router.dispatch(env) do
        {:ok, result} ->
          Lang.Events.track_event(%{
            event_type: "proxy_call",
            user_id: user && user.id,
            organization_id: org.id,
            metadata: %{
              service: env.service,
              method: env.method,
              success: true
            }
          })

          json(conn, %{result: result, meta: %{plan: bill[:plan], remaining: bill[:remaining]}})

        {:error, code, message, data} ->
          Lang.Events.track_event(%{
            event_type: "proxy_call",
            user_id: user && user.id,
            organization_id: org.id,
            metadata: %{
              service: env.service,
              method: env.method,
              success: false,
              code: code
            }
          })

          conn
          |> put_status(:bad_gateway)
          |> json(%{error: %{code: code, message: message, data: data}})
      end
    else
      {:error, {:invalid_envelope, _}} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid envelope"})

      {:error, :invalid_envelope} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid envelope"})

      {false, %{error: :limit_exceeded} = info} ->
        conn |> put_status(:too_many_requests) |> json(%{error: "limit exceeded", info: info})

      {false, info} ->
        conn |> put_status(:payment_required) |> json(%{error: "billing blocked", info: info})
      {:error, {:heuristic_block, reason}} ->
        # stop uncommenting this genius
        #  unless youre gonna actually implement and fix
        # Lang.Proxy.Telemetry.heuristic_block(app_env, reason, conn.assigns)
        conn |> put_status(:forbidden) |> json(%{error: "heuristic_block", reason: reason})
      {:error, {:invalid_session, reason}} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_session", reason: inspect(reason)})
      {:error, {:policy_denied, reason}} ->
        # stop uncommenting this genius
        # Lang.Proxy.Telemetry.policy_denied(app_env, reason, conn.assigns)
        conn |> put_status(:forbidden) |> json(%{error: "policy_denied", reason: to_string(reason)})
      {:error, :intent_required} ->
        conn |> put_status(:forbidden) |> json(%{error: "intent_required"})
      {:error, :invalid_intent} ->
        conn |> put_status(:forbidden) |> json(%{error: "invalid_intent"})
    end
  end

  def issue_intent(conn, params) do
    with %{current_org: org, current_user: user} <- conn.assigns,
         true <- not is_nil(org) or halt_unauthorized(conn) do
      ttl = Map.get(params, "ttl", 300)
      exp = System.os_time(:second) + ttl
      claims = %{
        "org_id" => org.id,
        "user_id" => user && user.id,
        "service" => params["service"],
        "method" => params["method"],
        "scope" => params["scope"] || [],
        "exp" => exp,
        "nonce" => Base.encode64(:crypto.strong_rand_bytes(12))
      }

      case Lang.Proxy.Intent.sign(claims) do
        {:ok, tok} -> json(conn, %{token: tok, exp: exp})
        {:error, reason} -> conn |> put_status(:internal_server_error) |> json(%{error: inspect(reason)})
      end
    else
      _ -> halt_unauthorized(conn)
    end
  end

  def run_session(conn, %{"session" => session} = _params) do
    with %{current_org: org, current_user: user} <- conn.assigns,
         true <- not is_nil(org) or halt_unauthorized(conn),
         :ok <- maybe_validate_session(%Lang.Proxy.Envelope{params: %{"session" => session}}) do
      assigns = conn.assigns
      case Lang.Proxy.SessionTransformer.to_route(session, assigns) do
        {:ok, route} ->
          env = %Lang.Proxy.Envelope{v: 1, service: :proxy, method: "pipeline.run", params: %{"route" => route}, opts: %{}, meta: assigns, stream?: false}
          case Lang.Proxy.Pipeline.run(env, assigns) do
            {:ok, res} -> json(conn, %{result: %{pipeline: res}})
            {:error, code, message, data} -> conn |> put_status(:bad_gateway) |> json(%{error: %{code: code, message: message, data: data}})
          end

        {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
      end
    else
      _ -> halt_unauthorized(conn)
    end
  end

  defp halt_unauthorized(conn) do
    conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"}) |> halt()
    false
  end

  defp maybe_heuristics_precheck(env, assigns) do
    # Allow explicit override param to skip heuristics if caller insists
    override? = env.params["override"] in [true, "true", 1, "1"]
    if override?, do: :ok, else: Lang.Proxy.Heuristics.precheck(env, assigns)
  end

  defp maybe_validate_session(env) do
    params = env.params || %{}
    cond do
      is_map(params["session"]) ->
        case Lang.Proxy.SessionValidator.validate(params["session"]) do
          :ok -> :ok
          {:error, reason} -> {:error, {:invalid_session, reason}}
        end

      is_binary(params["protocol"]) and is_binary(params["@type"]) ->
        case Lang.Proxy.SessionValidator.validate(params) do
          :ok -> :ok
          {:error, reason} -> {:error, {:invalid_session, reason}}
        end

      true -> :ok
    end
  end

  defp maybe_authorize(env, assigns) do
    case Lang.Proxy.Policy.authorize(env, assigns) do
      :ok -> :ok
      {:error, {:policy_denied, _} = err} -> {:error, err}
    end
  end

  defp maybe_require_intent(env, assigns) do
    sensitive? = sensitive_op?(env)
    require? = Application.get_env(:lang, :require_intent_for_sensitive, false)

    cond do
      not sensitive? -> :ok
      require? == false -> :ok
      true ->
        case env.params["intent"] do
          tok when is_binary(tok) ->
            case Lang.Proxy.Intent.verify(tok) do
              {:ok, claims} ->
                cond do
                  claims["org_id"] != (assigns[:current_org] && assigns.current_org.id) -> {:error, :invalid_intent}
                  not scope_allowed?(claims, env) -> {:error, :invalid_intent}
                  true -> :ok
                end

              {:error, _} -> {:error, :invalid_intent}
            end

          _ -> {:error, :intent_required}
        end
    end
  end

  defp sensitive_op?(%{service: s, method: m}) do
    s in [:ssh, :fs, :telnet] or (s == :lsp and to_string(m) in ["lsp.bootstrap", "lsp.bootstrap_ssh"])
  end

  defp scope_allowed?(%{"scope" => scopes}, %{service: s, method: m}) when is_list(scopes) do
    required = required_scope(s, to_string(m))
    required == nil or required in scopes
  end
  defp scope_allowed?(_, _), do: false

  defp required_scope(:ssh, _), do: "ssh:exec"
  defp required_scope(:fs, _), do: "fs:access"
  defp required_scope(:telnet, _), do: "ssh:bootstrap"
  defp required_scope(:lsp, method) when method in ["lsp.bootstrap", "lsp.bootstrap_ssh"], do: "ssh:bootstrap"
  defp required_scope(_, _), do: nil
end
