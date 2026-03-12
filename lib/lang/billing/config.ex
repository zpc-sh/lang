defmodule Lang.Billing.Config do
  @moduledoc """
  Helper module to access billing configuration from config/billing.exs

  This module provides a clean interface to access pricing plans, features,
  and limits without hardcoding values throughout the application.
  """

  @doc """
  Get all billing plans configuration
  """
  def plans do
    billing_config = Application.get_env(:lang, :billing, [])

    case billing_config do
      config when is_list(config) -> Keyword.get(config, :plans, %{})
      config when is_map(config) -> Map.get(config, :plans, %{})
      _ -> %{}
    end
  end

  @doc """
  Get a specific plan configuration
  """
  def plan(tier) when tier in [:free, :pro, :enterprise] do
    plans()[tier]
  end

  def plan(_), do: nil

  @doc """
  Get plan display name
  """
  def plan_name(tier) do
    case plan(tier) do
      %{display_name: name} -> name
      %{name: name} -> name
      _ -> "Unknown Plan"
    end
  end

  @doc """
  Get plan price in dollars
  """
  def plan_price_dollars(tier) do
    case plan(tier) do
      %{price_dollars: price} -> price
      _ -> 0
    end
  end

  @doc """
  Get plan price in cents
  """
  def plan_price_cents(tier) do
    case plan(tier) do
      %{price_cents: price} -> price
      _ -> 0
    end
  end

  @doc """
  Get formatted plan price string
  """
  def plan_price_string(tier) do
    case plan(tier) do
      %{price_dollars: 0} -> "Free"
      %{price_dollars: price, billing_interval: "month"} -> "$#{price}/month"
      %{price_dollars: price, billing_interval: "year"} -> "$#{price}/year"
      %{price_dollars: price} -> "$#{price}"
      _ -> "Custom"
    end
  end

  @doc """
  Get plan request limits per month
  """
  def plan_request_limit(tier) do
    case plan(tier) do
      %{requests_per_month: limit} -> limit
      %{limits: %{requests_per_month: limit}} -> limit
      # Default fallback
      _ -> 1000
    end
  end

  @doc """
  Get plan feature availability
  """
  def plan_has_feature?(tier, feature) do
    case plan(tier) do
      %{features: features} -> Map.get(features, feature, false)
      _ -> false
    end
  end

  @doc """
  Get plan limits
  """
  def plan_limits(tier) do
    case plan(tier) do
      %{limits: limits} -> limits
      _ -> %{}
    end
  end

  @doc """
  Get plan limit for specific type
  """
  def plan_limit(tier, limit_type) do
    plan_limits(tier)[limit_type]
  end

  @doc """
  Get all available plan tiers
  """
  def available_tiers do
    plans() |> Map.keys()
  end

  @doc """
  Check if a plan tier is valid
  """
  def valid_tier?(tier) do
    tier in available_tiers()
  end

  @doc """
  Get plan description
  """
  def plan_description(tier) do
    case plan(tier) do
      %{description: desc} -> desc
      _ -> ""
    end
  end

  @doc """
  Check if a plan is popular (has most popular badge)
  """
  def plan_popular?(tier) do
    case plan(tier) do
      %{popular: true} -> true
      _ -> false
    end
  end

  @doc """
  Get Stripe metadata for a plan
  """
  def plan_stripe_metadata(tier) do
    case plan(tier) do
      %{stripe_metadata: metadata} -> metadata
      _ -> %{}
    end
  end

  @doc """
  Get plan features for display
  """
  def plan_features(tier) do
    case plan(tier) do
      %{features: features} -> features
      _ -> %{}
    end
  end

  @doc """
  Get enabled features for a plan
  """
  def plan_enabled_features(tier) do
    plan_features(tier)
    |> Enum.filter(fn {_feature, enabled} -> enabled end)
    |> Enum.map(fn {feature, _} -> feature end)
  end

  @doc """
  Get disabled features for a plan
  """
  def plan_disabled_features(tier) do
    plan_features(tier)
    |> Enum.filter(fn {_feature, enabled} -> !enabled end)
    |> Enum.map(fn {feature, _} -> feature end)
  end

  @doc """
  Compare two plans and return upgrade path
  """
  def can_upgrade?(from_tier, to_tier) do
    from_price = plan_price_dollars(from_tier)
    to_price = plan_price_dollars(to_tier)

    to_price > from_price
  end

  @doc """
  Get the next tier upgrade option
  """
  def next_tier(:free), do: :pro
  def next_tier(:pro), do: :enterprise
  def next_tier(:enterprise), do: nil

  @doc """
  Get max team members for plan
  """
  def max_team_members(tier) do
    plan_limit(tier, :team_members) || 1
  end

  @doc """
  Get max API keys for plan
  """
  def max_api_keys(tier) do
    plan_limit(tier, :api_keys) || 1
  end

  @doc """
  Get data retention days for plan
  """
  def data_retention_days(tier) do
    plan_limit(tier, :data_retention_days) || 30
  end
end
