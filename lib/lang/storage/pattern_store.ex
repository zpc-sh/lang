defmodule Lang.Storage.PatternStore do
  @moduledoc """
  Service wrapper around ETS-backed Ash resource for local pattern storage.
  """

  alias Lang.Storage.PatternEntity

  @spec store_many([map()]) :: {:ok, [PatternEntity.t()]} | {:error, term()}
  def store_many(patterns) when is_list(patterns) do
    results =
      Enum.map(patterns, fn p ->
        attrs =
          case p do
            %{"content" => _} -> p
            %{:content => _} -> p
            other -> %{content: other}
          end

        case PatternEntity.store(attrs) do
          {:ok, rec} -> {:ok, rec}
          {:error, err} -> {:error, err}
        end
      end)

    {oks, errs} = Enum.split_with(results, &match?({:ok, _}, &1))

    if errs == [] do
      {:ok, Enum.map(oks, fn {:ok, rec} -> rec end)}
    else
      {:error, {:partial_failure, errs}}
    end
  end

  @spec get_many([String.t()]) :: {:ok, [PatternEntity.t()]} | {:error, term()}
  def get_many(ids) when is_list(ids) do
    PatternEntity.get_many(ids)
  end

  @spec update_confidence(String.t(), number() | Decimal.t()) :: {:ok, PatternEntity.t()} | {:error, term()}
  def update_confidence(id, confidence) when is_binary(id) do
    PatternEntity.update_confidence(id, decimal(confidence))
  end

  defp decimal(%Decimal{} = d), do: d
  defp decimal(n) when is_integer(n) or is_float(n), do: Decimal.from_float(n * 1.0)
  defp decimal(n) when is_binary(n), do: Decimal.new(n)
end
