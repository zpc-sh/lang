defmodule Lang.Billing.ConfigManager do
  @moduledoc """
  Configuration manager for billing plans and Stripe integration.

  This module provides a clean interface to the billing configuration
  defined in config/billing.exs, following proper Elixir conventions.

  ## Usage

      # Get plan configuration
      {:ok, plan} = Lang.Billing.ConfigManager.get_plan(:pro)

      # Check feature availability
      true = Lang.Billing.ConfigManager.has_feature?(:pro, :advanced_analytics)

      # Get all plans
      plans = Lang.Billing.ConfigManager.list_plans()

      # Validate configuration
      :ok = Lang.Billing.ConfigManager.validate_config()

  ## Features

  - Reads configuration from standard Elixir config system
  - Automatic plan validation on startup
  - Feature checking and plan comparison
  - Cost calculations and metrics
  - Environment-specific overrides

  """

  require Logger

  @doc """
  Gets configuration for a specific plan.
  Returns enhanced plan data with calculated metrics.
  """
  def get_plan(plan_type) when plan_type in [:free, :pro, :enterprise] do
    case get_raw_plan(plan_type) do
      nil -> {:error, :plan_not_found}
      plan_config -> {:ok, enhance_plan_config(plan_config, plan_type)}
    end
  end

  def get_plan(_invalid_plan), do: {:error, :invalid_plan_type}

  @doc """
  Gets plan configuration without error tuple (for internal use).
  Returns nil if plan doesn't exist.
  """
  def get_plan!(plan_type) do
    case get_plan(plan_type) do
      {:ok, plan} -> plan
      {:error, _} -> nil
    end
  end

  @doc """
  Lists all available plans with enhanced data.
  """
  def list_plans do
    plans_config()
    |> Enum.map(fn {plan_type, _config} ->
      case get_plan(plan_type) do
        {:ok, enhanced_plan} -> {plan_type, enhanced_plan}
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  @doc """
  Checks if a plan has a specific feature enabled.
  """
  def has_feature?(plan_type, feature_name) do
    case get_plan(plan_type) do
      {:ok, plan} ->
        features = Map.get(plan, :features, %{})
        Map.get(features, feature_name, false)

      {:error, _} ->
        false
    end
  end

  @doc """
  Gets all enabled features for a plan.
  """
  def get_enabled_features(plan_type) do
    case get_plan(plan_type) do
      {:ok, plan} ->
        features = Map.get(plan, :features, %{})

        features
        |> Enum.filter(fn {_feature, enabled} -> enabled == true end)
        |> Enum.map(fn {feature, _} -> feature end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Gets features organized by category for a plan.
  """
  def get_features_by_category(plan_type) do
    enabled_features = MapSet.new(get_enabled_features(plan_type))

    feature_categories =
      Application.get_env(:lang, :billing, %{}) |> Keyword.get(:feature_categories, %{})

    feature_categories
    |> Enum.map(fn {category, features} ->
      available_features =
        features
        |> Enum.filter(&MapSet.member?(enabled_features, &1))

      {category, available_features}
    end)
    |> Map.new()
  end

  @doc """
  Gets plan limits and usage constraints.
  """
  def get_plan_limits(plan_type) do
    case get_plan(plan_type) do
      {:ok, plan} -> {:ok, Map.get(plan, :limits, %{})}
      error -> error
    end
  end

  @doc """
  Checks if current usage is within plan limits.
  """
  def within_limits?(plan_type, usage_type, current_usage) do
    with {:ok, limits} <- get_plan_limits(plan_type),
         limit when not is_nil(limit) <- Map.get(limits, usage_type) do
      case limit do
        :unlimited -> true
        numeric_limit when is_integer(numeric_limit) -> current_usage <= numeric_limit
        _ -> false
      end
    else
      _ -> false
    end
  end

  @doc """
  Gets upgrade recommendation for a plan.
  """
  def get_upgrade_recommendation(current_plan) do
    case current_plan do
      :free ->
        free_plan = get_plan!(:free)
        pro_plan = get_plan!(:pro)

        if pro_plan do
          %{
            recommended: :pro,
            reason:
              "#{format_number(pro_plan.requests_per_month)} requests and advanced features",
            savings_text: format_savings(free_plan, pro_plan),
            new_features: get_feature_difference(:free, :pro),
            cost_comparison: get_cost_comparison(:free, :pro)
          }
        else
          nil
        end

      :pro ->
        pro_plan = get_plan!(:pro)
        enterprise_plan = get_plan!(:enterprise)

        if enterprise_plan do
          %{
            recommended: :enterprise,
            reason:
              "#{format_number(enterprise_plan.requests_per_month)} requests and enterprise features",
            savings_text: format_savings(pro_plan, enterprise_plan),
            new_features: get_feature_difference(:pro, :enterprise),
            cost_comparison: get_cost_comparison(:pro, :enterprise)
          }
        else
          nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Calculates overage costs for usage beyond plan limits.
  """
  def calculate_overage_cost(plan_type, usage_type, current_usage) do
    with {:ok, limits} <- get_plan_limits(plan_type),
         limit when is_integer(limit) <- Map.get(limits, usage_type),
         true <- current_usage > limit do
      overage_amount = current_usage - limit
      plan = get_plan!(plan_type)
      overage_config = billing_config() |> Keyword.get(:overage, %{})

      # Calculate overage rate
      overage_rate =
        case usage_type do
          :requests_per_month ->
            base_rate = Map.get(plan, :cost_per_1k, 0.0)
            multiplier = Map.get(overage_config, :requests_multiplier, 2.0)
            base_rate * multiplier

          _ ->
            0.0
        end

      overage_cost_cents =
        max(
          round(overage_amount / 1000 * overage_rate * 100),
          Map.get(overage_config, :minimum_charge_cents, 100)
        )

      %{
        overage_amount: overage_amount,
        overage_rate: overage_rate,
        overage_cost_cents: overage_cost_cents,
        overage_cost_dollars: overage_cost_cents / 100,
        grace_period_hours: Map.get(overage_config, :grace_period_hours, 24)
      }
    else
      _ ->
        %{
          overage_amount: 0,
          overage_cost_cents: 0,
          overage_cost_dollars: 0.0,
          grace_period_hours: 0
        }
    end
  end

  # Gets Stripe configuration settings.
  defp stripe_config do
    case billing_config() |> Keyword.get(:stripe, %{}) do
      stripe_config when is_map(stripe_config) -> stripe_config
      _ -> %{}
    end
  end

  @doc """
  Gets optimization settings for revenue features.
  """
  def optimization_config do
    billing_config() |> Keyword.get(:optimization, %{})
  end

  @doc """
  Validates the current billing configuration.
  Returns :ok if valid, {:error, reasons} if invalid.
  """
  def validate_config do
    errors = []

    # Validate plans exist
    errors =
      if map_size(plans_config()) == 0 do
        ["No billing plans configured" | errors]
      else
        errors
      end

    # Validate each plan
    plan_errors =
      plans_config()
      |> Enum.flat_map(fn {plan_type, plan_config} ->
        validate_plan_config(plan_type, plan_config)
      end)

    errors = errors ++ plan_errors

    # Validate Stripe configuration
    stripe_errors = validate_stripe_config()
    errors = errors ++ stripe_errors

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  Gets current configuration environment.
  """
  def config_env, do: Application.get_env(:lang, :environment, Mix.env())

  # Private helper functions

  defp billing_config do
    Application.get_env(:lang, :billing, %{})
  end

  defp plans_config do
    billing_config() |> Keyword.get(:plans, %{})
  end

  defp get_raw_plan(plan_type) do
    plans_config() |> Map.get(plan_type)
  end

  defp enhance_plan_config(plan_config, plan_type) do
    features = Map.get(plan_config, :features, %{})

    plan_config
    |> Map.put(:plan_type, plan_type)
    |> Map.put(:cost_per_1k, calculate_cost_per_1k(plan_config))
    |> Map.put(:feature_count, count_enabled_features(features))
    |> Map.put(:is_paid, Map.get(plan_config, :price_cents, 0) > 0)
    |> Map.put(:formatted_price, format_price(plan_config))
  end

  defp calculate_cost_per_1k(plan_config) do
    price_cents = Map.get(plan_config, :price_cents, 0)
    requests_per_month = Map.get(plan_config, :requests_per_month, 1)

    if requests_per_month > 0 and price_cents > 0 do
      Float.round(price_cents / 100 / (requests_per_month / 1000), 2)
    else
      0.0
    end
  end

  defp count_enabled_features(features) when is_map(features) do
    features
    |> Enum.count(fn {_feature, enabled} -> enabled == true end)
  end

  defp count_enabled_features(_), do: 0

  defp format_price(plan_config) do
    price_dollars = Map.get(plan_config, :price_dollars, 0)
    interval = Map.get(plan_config, :billing_interval, "month")

    case price_dollars do
      0 -> "Free"
      price -> "$#{price}/#{interval}"
    end
  end

  defp format_number(number) when number >= 1_000_000 do
    "#{div(number, 1_000_000)}M"
  end

  defp format_number(number) when number >= 1_000 do
    "#{div(number, 1_000)}K"
  end

  defp format_number(number), do: to_string(number)

  defp format_savings(from_plan, to_plan) do
    if (from_plan && to_plan && from_plan.cost_per_1k > 0) and to_plan.cost_per_1k > 0 do
      savings_percent = round((1 - to_plan.cost_per_1k / from_plan.cost_per_1k) * 100)

      if savings_percent > 0 do
        "Save #{savings_percent}% per request"
      else
        "Premium features and scale"
      end
    else
      "Advanced features included"
    end
  end

  defp get_feature_difference(from_plan, to_plan) do
    from_features = MapSet.new(get_enabled_features(from_plan))
    to_features = MapSet.new(get_enabled_features(to_plan))

    MapSet.difference(to_features, from_features)
    |> MapSet.to_list()
  end

  defp get_cost_comparison(from_plan, to_plan) do
    from_config = get_plan!(from_plan)
    to_config = get_plan!(to_plan)

    if from_config && to_config do
      %{
        from: %{
          price_dollars: from_config.price_dollars,
          cost_per_1k: from_config.cost_per_1k,
          requests_per_month: from_config.requests_per_month
        },
        to: %{
          price_dollars: to_config.price_dollars,
          cost_per_1k: to_config.cost_per_1k,
          requests_per_month: to_config.requests_per_month
        }
      }
    else
      %{}
    end
  end

  defp validate_plan_config(plan_type, plan_config) do
    errors = []

    # Required fields
    required_fields = [:name, :price_cents, :requests_per_month, :description]

    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(plan_config, &1))

    errors =
      if length(missing_fields) > 0 do
        ["Plan #{plan_type} missing required fields: #{Enum.join(missing_fields, ", ")}" | errors]
      else
        errors
      end

    # Validate price
    price_cents = Map.get(plan_config, :price_cents, 0)

    errors =
      if not is_integer(price_cents) or price_cents < 0 do
        ["Plan #{plan_type} has invalid price_cents: #{price_cents}" | errors]
      else
        errors
      end

    # Validate requests
    requests = Map.get(plan_config, :requests_per_month, 0)

    errors =
      if not is_integer(requests) or requests < 0 do
        ["Plan #{plan_type} has invalid requests_per_month: #{requests}" | errors]
      else
        errors
      end

    errors
  end

  defp validate_stripe_config do
    errors = []
    stripe_config = stripe_config()

    # Check webhook events are configured
    webhook_events = Map.get(stripe_config, :webhook_events, [])

    errors =
      if length(webhook_events) == 0 do
        ["No Stripe webhook events configured" | errors]
      else
        errors
      end

    # Check required webhook events
    required_events = [
      "customer.subscription.created",
      "customer.subscription.updated",
      "customer.subscription.deleted",
      "invoice.payment_succeeded"
    ]

    missing_events =
      required_events
      |> Enum.reject(&Enum.member?(webhook_events, &1))

    errors =
      if length(missing_events) > 0 do
        ["Missing required webhook events: #{Enum.join(missing_events, ", ")}" | errors]
      else
        errors
      end

    errors
  end
end
