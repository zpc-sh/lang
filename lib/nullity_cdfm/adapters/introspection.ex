defmodule Nullity.CDFM.Adapters.Introspection do
  @moduledoc """
  Behaviour for code introspection (is MFA exported?).
  """

  @callback exported?(module :: atom(), function :: atom(), arity :: non_neg_integer()) :: boolean()
end

