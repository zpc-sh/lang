defmodule Lang.Proxy.Telemetry do
  @moduledoc "Telemetry helpers for proxy layer"

  def heuristic_block(env, reason, assigns) do
    :telemetry.execute([:lang, :proxy, :heuristic_block], %{count: 1}, meta(env, assigns, %{reason: reason}))
  end

  def policy_denied(env, reason, assigns) do
    :telemetry.execute([:lang, :proxy, :policy_denied], %{count: 1}, meta(env, assigns, %{reason: reason}))
  end

  defp meta(env, assigns, extra) do
    %{
      service: env.service,
      method: env[:method],
      org_id: assigns[:current_org] && assigns.current_org.id,
      user_id: assigns[:current_user] && assigns.current_user.id
    }
    |> Map.merge(extra)
  end
end

