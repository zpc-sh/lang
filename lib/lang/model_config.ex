defmodule Lang.ModelConfig do
  @moduledoc """
  Configuration for AI model pricing, context windows, and capabilities.

  This module provides a centralized configuration for all supported AI models
  across different providers, including their pricing per million tokens,
  context windows, and other capabilities.
  """

  @pricing_data %{
    anthropic: %{
      "claude-3-5-sonnet-20241022" => %{input: 3.0, output: 15.0},
      "claude-3-5-sonnet-20240620" => %{input: 3.0, output: 15.0},
      "claude-3-5-haiku-20241022" => %{input: 1.0, output: 5.0},
      "claude-3-opus-20240229" => %{input: 15.0, output: 75.0},
      "claude-3-sonnet-20240229" => %{input: 3.0, output: 15.0},
      "claude-3-haiku-20240307" => %{input: 0.25, output: 1.25}
    },
    openai: %{
      "gpt-4o" => %{input: 2.5, output: 10.0},
      "gpt-4o-mini" => %{input: 0.15, output: 0.6},
      "gpt-4-turbo" => %{input: 10.0, output: 30.0},
      "gpt-4" => %{input: 30.0, output: 60.0},
      "gpt-3.5-turbo" => %{input: 0.5, output: 1.5},
      "o1-preview" => %{input: 15.0, output: 60.0},
      "o1-mini" => %{input: 3.0, output: 12.0}
    },
    openrouter: %{
      "anthropic/claude-3.5-sonnet" => %{input: 3.0, output: 15.0},
      "anthropic/claude-3-opus" => %{input: 15.0, output: 75.0},
      "openai/gpt-4o" => %{input: 2.5, output: 10.0},
      "openai/gpt-4o-mini" => %{input: 0.15, output: 0.6},
      "meta-llama/llama-3.1-405b-instruct" => %{input: 2.7, output: 2.7},
      "meta-llama/llama-3.1-70b-instruct" => %{input: 0.52, output: 0.75},
      "google/gemini-pro-1.5" => %{input: 1.25, output: 5.0},
      "mistralai/mistral-large" => %{input: 3.0, output: 9.0}
    },
    gemini: %{
      "gemini-1.5-pro" => %{input: 1.25, output: 5.0},
      "gemini-1.5-flash" => %{input: 0.075, output: 0.3},
      "gemini-1.0-pro" => %{input: 0.5, output: 1.5}
    },
    bedrock: %{
      "anthropic.claude-3-5-sonnet-20241022-v2:0" => %{input: 3.0, output: 15.0},
      "anthropic.claude-3-5-haiku-20241022-v1:0" => %{input: 1.0, output: 5.0},
      "anthropic.claude-3-opus-20240229-v1:0" => %{input: 15.0, output: 75.0},
      "anthropic.claude-3-sonnet-20240229-v1:0" => %{input: 3.0, output: 15.0},
      "anthropic.claude-3-haiku-20240307-v1:0" => %{input: 0.25, output: 1.25},
      "meta.llama3-1-405b-instruct-v1:0" => %{input: 2.65, output: 3.5},
      "meta.llama3-1-70b-instruct-v1:0" => %{input: 0.265, output: 0.35}
    },
    ollama: %{
      # Local models - no cost
      "llama3.1:8b" => %{input: 0.0, output: 0.0},
      "llama3.1:70b" => %{input: 0.0, output: 0.0},
      "llama3.2:3b" => %{input: 0.0, output: 0.0},
      "codestral:22b" => %{input: 0.0, output: 0.0},
      "mixtral:8x7b" => %{input: 0.0, output: 0.0},
      "phi3:3.8b" => %{input: 0.0, output: 0.0}
    },
    qwen: %{
      "qwen2.5-72b-instruct" => %{input: 0.9, output: 0.9},
      "qwen2.5-32b-instruct" => %{input: 0.7, output: 0.7},
      "qwen2.5-14b-instruct" => %{input: 0.3, output: 0.3},
      "qwen2.5-7b-instruct" => %{input: 0.18, output: 0.18},
      "qwen2-72b-instruct" => %{input: 0.9, output: 0.9},
      "qwen2-7b-instruct" => %{input: 0.18, output: 0.18},
      "qwen-turbo" => %{input: 0.3, output: 0.6},
      "qwen-plus" => %{input: 4.0, output: 4.0},
      "qwen-max" => %{input: 20.0, output: 20.0}
    },
    codex: %{
      "code-davinci-002" => %{input: 10.0, output: 10.0},
      "code-davinci-001" => %{input: 10.0, output: 10.0},
      "code-cushman-002" => %{input: 2.0, output: 2.0},
      "code-cushman-001" => %{input: 2.0, output: 2.0},
      # Subscription-based
      "github-copilot" => %{input: 0.0, output: 0.0},
      "codex-instruct" => %{input: 8.0, output: 8.0}
    }
  }

  @doc """
  Get pricing information for a specific provider and model.

  Returns a map with :input and :output keys representing cost per million tokens,
  or nil if the provider/model combination is not found.

  ## Examples

      iex> Lang.ModelConfig.get_pricing(:openai, "gpt-4o")
      %{input: 2.5, output: 10.0}

      iex> Lang.ModelConfig.get_pricing(:anthropic, "claude-3-5-sonnet-20241022")
      %{input: 3.0, output: 15.0}

      iex> Lang.ModelConfig.get_pricing(:unknown, "model")
      nil
  """
  @spec get_pricing(atom(), String.t()) :: %{input: float(), output: float()} | nil
  def get_pricing(provider, model) do
    @pricing_data
    |> Map.get(provider)
    |> case do
      nil -> nil
      provider_pricing -> Map.get(provider_pricing, model)
    end
  end

  @doc """
  Get all pricing data for a specific provider.

  ## Examples

      iex> Lang.ModelConfig.get_all_pricing(:openai)
      %{
        "gpt-4o" => %{input: 2.5, output: 10.0},
        "gpt-4o-mini" => %{input: 0.15, output: 0.6},
        ...
      }
  """
  @spec get_all_pricing(atom()) :: map() | %{}
  def get_all_pricing(provider) do
    Map.get(@pricing_data, provider, %{})
  end

  @doc """
  List all available providers.

  ## Examples

      iex> Lang.ModelConfig.list_providers()
      [:anthropic, :openai, :openrouter, :gemini, :bedrock, :ollama]
  """
  @spec list_providers() :: [atom()]
  def list_providers do
    Map.keys(@pricing_data)
  end

  @doc """
  List all models for a specific provider.

  ## Examples

      iex> Lang.ModelConfig.list_models(:openai)
      ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", ...]
  """
  @spec list_models(atom()) :: [String.t()]
  def list_models(provider) do
    @pricing_data
    |> Map.get(provider, %{})
    |> Map.keys()
  end

  @doc """
  Check if a provider/model combination exists.

  ## Examples

      iex> Lang.ModelConfig.model_exists?(:openai, "gpt-4o")
      true

      iex> Lang.ModelConfig.model_exists?(:openai, "nonexistent")
      false
  """
  @spec model_exists?(atom(), String.t()) :: boolean()
  def model_exists?(provider, model) do
    get_pricing(provider, model) != nil
  end

  @doc """
  Get the cheapest model for a provider based on input token cost.

  ## Examples

      iex> Lang.ModelConfig.cheapest_model(:openai)
      {"gpt-4o-mini", %{input: 0.15, output: 0.6}}
  """
  @spec cheapest_model(atom()) :: {String.t(), map()} | nil
  def cheapest_model(provider) do
    provider
    |> get_all_pricing()
    |> Enum.min_by(fn {_model, pricing} -> pricing.input end, fn -> nil end)
  end

  @doc """
  Get models sorted by input token cost (cheapest first).

  ## Examples

      iex> Lang.ModelConfig.models_by_cost(:openai)
      [
        {"gpt-4o-mini", %{input: 0.15, output: 0.6}},
        {"gpt-3.5-turbo", %{input: 0.5, output: 1.5}},
        ...
      ]
  """
  @spec models_by_cost(atom()) :: [{String.t(), map()}]
  def models_by_cost(provider) do
    provider
    |> get_all_pricing()
    |> Enum.sort_by(fn {_model, pricing} -> pricing.input end)
  end
end
