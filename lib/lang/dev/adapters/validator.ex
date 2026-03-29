defmodule Lang.Dev.Validator do
  @moduledoc "Behaviour for JSON‑LD validation"
  @callback validate(map()) :: :ok | {:error, term()}
end

defmodule Lang.Dev.Validator.Default do
  @moduledoc "Default validator delegates to Lang.Dev.JSONLDHelper.validate/1"
  @behaviour Lang.Dev.Validator
  def validate(map), do: Lang.Dev.JSONLDHelper.validate(map)
end

