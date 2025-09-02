defmodule LangWeb.Plugs.FeatureEntitlementPlug do
  @moduledoc """
  Feature entitlement guard based on organization plan/tier.

  Options:
  - :feature - atom indicating the required feature (:signed_exports)
  """

  import Plug.Conn

  @allowed_tiers MapSet.new([:pro, :professional, :enterprise])

  def init(opts), do: opts

  def call(conn, opts) do
    feature = Keyword.get(opts, :feature)
    org = conn.assigns[:current_org]

    if entitled?(org, feature) do
      conn
    else
      conn
      |> Phoenix.Controller.put_status(:payment_required)
      |> Phoenix.Controller.json(%{error: "feature_not_enabled", feature: to_string(feature)})
      |> halt()
    end
  end

  defp entitled?(nil, _), do: false

  defp entitled?(org, :signed_exports) do
    features = Map.get(org, :features) || %{}
    case fetch_flag(features, :signed_exports) do
      true ->
        true
      _ ->
        tier = Map.get(org, :plan) || Map.get(org, :subscription_tier) || Map.get(org, :tier)
        if tier in @allowed_tiers do
          true
        else
          System.get_env("ENABLE_SIGNED_EXPORTS_FOR_FREE") in ["1", "true", "on"]
        end
    end
  end

  defp entitled?(_org, _feature), do: false

  defp fetch_flag(map, key) when is_map(map) do
    Map.get(map, key) or Map.get(map, to_string(key))
  end
end