defmodule Lang.Providers.Capabilities do
  @moduledoc """
  Comprehensive capability normalization and querying system for AI providers.

  This module provides a unified interface for querying provider capabilities
  across different AI services. It normalizes capability names and provides
  methods to find providers and models that support specific features.

  ## Features

  - Normalizes capability names across providers
  - Queries provider-level and model-level capabilities
  - Finds providers and models supporting specific features
  - Human-readable capability display names
  - Comprehensive capability mapping system

  ## Usage

      # Check if a provider supports a capability
      Capabilities.supports?(:openai, :function_calling)

      # Find all providers that support vision
      Capabilities.find_providers(:vision)

      # Get all models that support code execution
      Capabilities.find_models(:code_execution)

      # Get normalized capability summary for a provider
      Capabilities.get_provider_capability_summary(:anthropic)
  """

  alias Lang.Providers.Provider

  # Capability normalization mappings
  # Maps various provider-specific names to our normalized capability names
  @capability_mappings %{
    # Function calling variations
    "tools" => :function_calling,
    "tool_use" => :function_calling,
    "functions" => :function_calling,
    "function_call" => :function_calling,
    "parallel_tool_calls" => :parallel_function_calling,

    # Image generation
    "images" => :image_generation,
    "dalle" => :image_generation,
    "image_gen" => :image_generation,
    "text_to_image" => :image_generation,

    # Speech synthesis
    "tts" => :speech_synthesis,
    "text_to_speech" => :speech_synthesis,
    "audio_generation" => :speech_synthesis,
    "speech_generation" => :speech_synthesis,

    # Speech recognition
    "whisper" => :speech_recognition,
    "stt" => :speech_recognition,
    "speech_to_text" => :speech_recognition,
    "audio_transcription" => :speech_recognition,
    "transcribe" => :speech_recognition,

    # Embeddings
    "embed" => :embeddings,
    "embedding" => :embeddings,
    "text_embedding" => :embeddings,
    "vectorization" => :embeddings,

    # Computer interaction
    "computer_use" => :computer_interaction,
    "desktop_control" => :computer_interaction,
    "screen_control" => :computer_interaction,

    # Vision/image understanding
    "image_understanding" => :vision,
    "visual_understanding" => :vision,
    "image_input" => :vision,
    "multimodal" => :vision,

    # Audio understanding
    "audio_understanding" => :audio_input,
    "audio_analysis" => :audio_input,
    "sound_input" => :audio_input,

    # JSON/structured output
    "json" => :json_mode,
    "json_output" => :json_mode,
    "structured_data" => :structured_outputs,
    "typed_outputs" => :structured_outputs,

    # Context features
    "extended_context" => :long_context,
    "large_context" => :long_context,
    "context_window" => :long_context,

    # Caching features
    "prompt_cache" => :prompt_caching,
    "context_cache" => :context_caching,
    "conversation_cache" => :context_caching,

    # System messages
    "system_prompt" => :system_messages,
    "system_instruction" => :system_messages,

    # Reasoning
    "chain_of_thought" => :reasoning,
    "cot" => :reasoning,
    "deep_thinking" => :reasoning,

    # Code features
    "code_exec" => :code_execution,
    "code_runner" => :code_execution,
    "code_interpreter" => :code_execution,

    # Assistants
    "assistant_api" => :assistants_api,
    "assistants" => :assistants_api,

    # Fine-tuning
    "fine_tune" => :fine_tuning,
    "finetuning" => :fine_tuning,
    "model_training" => :fine_tuning,

    # Grounding/search
    "web_grounding" => :grounding,
    "search_grounding" => :grounding,
    "rag" => :grounding,

    # Streaming
    "stream" => :streaming,
    "sse" => :streaming,
    "server_sent_events" => :streaming
  }

  # Inverse mappings for display purposes
  @display_names %{
    function_calling: "Function Calling",
    parallel_function_calling: "Parallel Function Calling",
    image_generation: "Image Generation",
    speech_synthesis: "Speech Synthesis (TTS)",
    speech_recognition: "Speech Recognition (STT)",
    embeddings: "Text Embeddings",
    computer_interaction: "Computer Use",
    vision: "Vision/Image Understanding",
    audio_input: "Audio Understanding",
    json_mode: "JSON Mode",
    structured_outputs: "Structured Outputs",
    long_context: "Extended Context Window",
    prompt_caching: "Prompt Caching",
    context_caching: "Context Caching",
    system_messages: "System Messages",
    reasoning: "Advanced Reasoning",
    code_execution: "Code Execution",
    assistants_api: "Assistants API",
    fine_tuning: "Fine-tuning",
    grounding: "Grounding/Web Search",
    streaming: "Streaming (Server-Sent Events)"
  }

  # Provider list - matches the existing provider system
  @providers [
    :anthropic,
    :openai,
    :opencode,
    :gemini,
    :xai
  ]

  # Base capability definitions for each provider
  @provider_capabilities %{
    anthropic: %{
      features: [
        :function_calling,
        :vision,
        :reasoning,
        :system_messages,
        :streaming,
        :long_context
      ],
      specializations: [:security, :analysis, :diagnostics, :safety, :detailed_review],
      context_window: 200_000,
      supports_tools: true,
      supports_vision: true,
      supports_system: true
    },
    openai: %{
      features: [
        :function_calling,
        :vision,
        :image_generation,
        :speech_synthesis,
        :speech_recognition,
        :embeddings,
        :assistants_api,
        :fine_tuning,
        :json_mode,
        :streaming
      ],
      specializations: [:general_purpose, :code_generation, :creative_writing],
      context_window: 128_000,
      supports_tools: true,
      supports_vision: true,
      supports_system: true
    },
    opencode: %{
      features: [:function_calling, :code_execution, :streaming, :json_mode],
      specializations: [:code_generation, :development, :debugging],
      context_window: 32_000,
      supports_tools: true,
      supports_vision: false,
      supports_system: true
    },
    gemini: %{
      features: [:function_calling, :vision, :grounding, :reasoning, :streaming, :long_context],
      specializations: [:research, :analysis, :multimodal],
      context_window: 1_000_000,
      supports_tools: true,
      supports_vision: true,
      supports_system: true
    },
    xai: %{
      features: [:function_calling, :reasoning, :streaming, :json_mode],
      specializations: [:reasoning, :analysis, :research],
      context_window: 128_000,
      supports_tools: true,
      supports_vision: false,
      supports_system: true
    }
  }

  @doc """
  Check if a provider supports a capability (normalized).

  This checks both provider-level capabilities and model-level capabilities.

  ## Examples

      iex> Capabilities.supports?(:openai, :function_calling)
      true

      iex> Capabilities.supports?(:anthropic, "tools")
      true

      iex> Capabilities.supports?(:opencode, :image_generation)
      false
  """
  @spec supports?(atom(), atom() | String.t()) :: boolean()
  def supports?(provider, feature) do
    normalized_feature = normalize_capability(feature)

    case get_provider_info(provider) do
      {:ok, info} ->
        normalized_feature in info.features

      {:error, _} ->
        false
    end
  end

  @doc """
  Check if a specific model supports a capability (normalized).

  Note: This is a placeholder for future model-specific capability tracking.
  Currently delegates to provider-level capabilities.

  ## Examples

      iex> Capabilities.model_supports?(:openai, "gpt-4o", :vision)
      true

      iex> Capabilities.model_supports?(:anthropic, "claude-3-5-sonnet", :function_calling)
      true
  """
  @spec model_supports?(atom(), String.t(), atom() | String.t()) :: boolean()
  def model_supports?(provider, _model_id, feature) do
    # For now, delegate to provider-level capabilities
    # In the future, this could query model-specific capabilities
    supports?(provider, feature)
  end

  @doc """
  Find all providers that support a capability (normalized).

  ## Examples

      iex> Capabilities.find_providers(:function_calling)
      [:anthropic, :gemini, :openai, :opencode, :xai]

      iex> Capabilities.find_providers(:vision)
      [:anthropic, :gemini, :openai]

      iex> Capabilities.find_providers("image_generation")
      [:openai]
  """
  @spec find_providers(atom() | String.t()) :: [atom()]
  def find_providers(feature) do
    normalized_feature = normalize_capability(feature)

    @providers
    |> Enum.filter(&supports?(&1, normalized_feature))
    |> Enum.sort()
  end

  @doc """
  Find all models that support a capability (normalized).

  Returns a list of {provider, model} tuples. Currently returns a representative
  set of models based on provider capabilities.

  ## Examples

      iex> Capabilities.find_models(:function_calling)
      [
        {:anthropic, "claude-3-5-sonnet-20241022"},
        {:gemini, "gemini-1.5-pro"},
        {:openai, "gpt-4o"},
        {:opencode, "codestral-latest"},
        {:xai, "grok-2-latest"}
      ]
  """
  @spec find_models(atom() | String.t()) :: [{atom(), String.t()}]
  def find_models(feature) do
    providers = find_providers(feature)

    # Return representative models for each provider
    Enum.map(providers, fn provider ->
      model = get_representative_model(provider)
      {provider, model}
    end)
  end

  @doc """
  Group models by a specific capability.

  Returns a map where the keys are provider names and values are lists
  of models that support the given capability.

  ## Examples

      iex> Capabilities.models_by_capability(:vision)
      %{
        anthropic: ["claude-3-5-sonnet-20241022", "claude-3-opus-20240229"],
        gemini: ["gemini-1.5-pro", "gemini-1.5-flash"],
        openai: ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"]
      }
  """
  @spec models_by_capability(atom() | String.t()) :: %{atom() => [String.t()]}
  def models_by_capability(capability) do
    providers = find_providers(capability)

    Enum.reduce(providers, %{}, fn provider, acc ->
      models = get_models_for_capability(provider, capability)
      Map.put(acc, provider, models)
    end)
  end

  @doc """
  Get normalized capability name.

  ## Examples

      iex> Capabilities.normalize_capability("tools")
      :function_calling

      iex> Capabilities.normalize_capability(:vision)
      :vision

      iex> Capabilities.normalize_capability("unknown_capability")
      :unknown_capability
  """
  @spec normalize_capability(atom() | String.t()) :: atom()
  def normalize_capability(feature) when is_atom(feature) do
    normalize_capability(to_string(feature))
  end

  def normalize_capability(feature) when is_binary(feature) do
    # First check if it's in our mappings
    normalized = Map.get(@capability_mappings, feature)

    if normalized do
      normalized
    else
      # Try with underscores converted to match our atom style
      feature_string =
        feature
        |> String.downcase()
        |> String.replace("-", "_")

      # Check if this string form exists in our mappings
      case Map.get(@capability_mappings, feature_string) do
        nil -> find_normalized_capability(feature_string)
        mapped -> mapped
      end
    end
  end

  @doc """
  Get human-readable name for a capability.

  ## Examples

      iex> Capabilities.display_name(:function_calling)
      "Function Calling"

      iex> Capabilities.display_name(:vision)
      "Vision/Image Understanding"

      iex> Capabilities.display_name(:unknown_feature)
      "Unknown feature"
  """
  @spec display_name(atom()) :: String.t()
  def display_name(capability) do
    Map.get(
      @display_names,
      capability,
      to_string(capability) |> String.replace("_", " ") |> String.capitalize()
    )
  end

  @doc """
  List all normalized capability names.

  ## Examples

      iex> Capabilities.list_capabilities()
      [:assistants_api, :audio_input, :code_execution, ...]
  """
  @spec list_capabilities() :: [atom()]
  def list_capabilities do
    @display_names
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Get detailed capability information for a provider.

  Returns both provider-level capabilities with normalization applied.

  ## Examples

      iex> Capabilities.get_provider_capability_summary(:openai)
      %{
        provider: :openai,
        features: [:function_calling, :vision, :image_generation, ...],
        specializations: [:general_purpose, :code_generation, :creative_writing],
        context_window: 128_000,
        supports_tools: true,
        supports_vision: true,
        supports_system: true
      }
  """
  @spec get_provider_capability_summary(atom()) :: map()
  def get_provider_capability_summary(provider) do
    case get_provider_info(provider) do
      {:ok, info} ->
        Map.put(info, :provider, provider)

      {:error, reason} ->
        %{
          provider: provider,
          error: reason,
          features: [],
          specializations: [],
          context_window: 0,
          supports_tools: false,
          supports_vision: false,
          supports_system: false
        }
    end
  end

  @doc """
  Get all providers and their capabilities in a structured format.

  ## Examples

      iex> Capabilities.get_all_capabilities()
      %{
        anthropic: %{features: [...], specializations: [...], ...},
        openai: %{features: [...], specializations: [...], ...},
        ...
      }
  """
  @spec get_all_capabilities() :: %{atom() => map()}
  def get_all_capabilities do
    @providers
    |> Enum.reduce(%{}, fn provider, acc ->
      summary = get_provider_capability_summary(provider)
      Map.put(acc, provider, Map.delete(summary, :provider))
    end)
  end

  @doc """
  Find the best provider for a given set of capabilities.

  Returns the provider that supports the most requested capabilities,
  with ties broken by provider preference order.

  ## Examples

      iex> Capabilities.find_best_provider([:function_calling, :vision])
      :openai

      iex> Capabilities.find_best_provider([:reasoning, :long_context])
      :anthropic
  """
  @spec find_best_provider([atom() | String.t()]) :: atom() | nil
  def find_best_provider(required_capabilities) do
    normalized_caps = Enum.map(required_capabilities, &normalize_capability/1)

    @providers
    |> Enum.map(fn provider ->
      supported_count =
        normalized_caps
        |> Enum.count(&supports?(provider, &1))

      {provider, supported_count}
    end)
    |> Enum.filter(fn {_provider, count} -> count > 0 end)
    |> Enum.sort_by(fn {_provider, count} -> count end, :desc)
    |> case do
      [] -> nil
      [{provider, _count} | _] -> provider
    end
  end

  @doc """
  Check if all required capabilities are supported by a provider.

  ## Examples

      iex> Capabilities.supports_all?(:openai, [:function_calling, :vision])
      true

      iex> Capabilities.supports_all?(:opencode, [:vision, :image_generation])
      false
  """
  @spec supports_all?(atom(), [atom() | String.t()]) :: boolean()
  def supports_all?(provider, required_capabilities) do
    required_capabilities
    |> Enum.all?(&supports?(provider, &1))
  end

  # Private helper functions

  defp get_provider_info(provider) do
    case Map.get(@provider_capabilities, provider) do
      nil -> {:error, :provider_not_found}
      info -> {:ok, info}
    end
  end

  defp get_representative_model(provider) do
    # Return a representative model for each provider
    case provider do
      :anthropic -> "claude-3-5-sonnet-20241022"
      :openai -> "gpt-4o"
      :opencode -> "codestral-latest"
      :gemini -> "gemini-1.5-pro"
      :xai -> "grok-2-latest"
      _ -> "default-model"
    end
  end

  defp get_models_for_capability(provider, _capability) do
    # Return a list of models that support the capability for the provider
    # This is a simplified implementation - in practice, this would query
    # model-specific capabilities
    case provider do
      :anthropic ->
        ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]

      :openai ->
        ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4"]

      :opencode ->
        ["codestral-latest", "codestral-22b"]

      :gemini ->
        ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"]

      :xai ->
        ["grok-2-latest", "grok-2-mini"]

      _ ->
        []
    end
  end

  # Helper function to find normalized capability
  defp find_normalized_capability(feature_string) do
    feature_atom = String.to_atom(feature_string)

    if feature_atom in Map.keys(@display_names) do
      feature_atom
    else
      # Return as-is if not found in mappings
      feature_atom
    end
  end
end
