defmodule Nullity.CDFM.Generator do
  @moduledoc """
  High-level generator entry points. Accepts normalized specs and emits
  generated files (handlers, registry, docs, tests) using template-based
  formats. Designed to be carved out into a library later.
  """

  alias CDFM.Formats.BaseGenerator, as: Base

  @type generated_file :: %{path: String.t(), content: iodata(), type: atom(), mode: atom(), description: String.t()}

  @doc """
  Generate code for a single blueprint using a given format module
  (which `use`s CDFM.Formats.BaseGenerator) and options.
  """
  @spec generate(module(), map(), keyword()) :: {:ok, %{files: [generated_file()], metadata: map()}} | {:error, String.t()}
  def generate(format_module, blueprint, opts \\ []) when is_atom(format_module) and is_map(blueprint) do
    with :ok <- ensure_implements?(format_module),
         :ok <- call_validators(format_module, blueprint) do
      format_module.generate(blueprint, opts)
    end
  end

  defp ensure_implements?(mod) do
    behaviours = mod.module_info(:attributes)[:behaviour] || []
    if CDFM.Formats.BaseGenerator in behaviours, do: :ok, else: {:error, "format module does not implement BaseGenerator"}
  end

  defp call_validators(mod, blueprint) do
    case mod.validate_blueprint(blueprint) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

