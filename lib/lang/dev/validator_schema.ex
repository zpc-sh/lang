defmodule Lang.Dev.Validator.Schema do
  @moduledoc """
  Simple JSON‑LD schema validator for dev use.

  - Ensures required keys and types.
  - Delegates identifier checks to JSONLDHelper.validate/1 for action id constraints.
  - Can be extended with stricter rules without changing call sites.
  """

  @behaviour Lang.Dev.Validator

  @impl true
  def validate(map) when is_map(map) do
    with :ok <- Lang.Dev.JSONLDHelper.validate(map),
         :ok <- check_types(map) do
      :ok
    end
  end

  defp check_types(map) do
    # Basic constraints commonly expected in our JSON‑LD models
    cond do
      not is_binary(Map.get(map, "lds:action")) -> {:error, {:type, {:"lds:action", :string}}}
      Map.has_key?(map, "version") and not is_binary(map["version"]) -> {:error, {:type, {:version, :string}}}
      Map.has_key?(map, "id") and not (is_binary(map["id"]) or is_number(map["id"])) -> {:error, {:type, {:id, :string_or_number}}}
      Map.has_key?(map, "type") and not (is_binary(map["type"]) or is_map(map["type"]) or is_list(map["type"])) -> {:error, {:type, {:type, :string_or_map_or_list}}}
      true -> :ok
    end
  end
end

