defmodule Nullity.CDFM.Adapters.Store do
  @moduledoc """
  Behaviour for persisting spec data (e.g., to Ash resources or in-memory).
  """

  @callback upsert_method(method :: map()) :: {:ok, any()} | {:error, term()}
  @callback read_all_methods() :: {:ok, list()} | {:error, term()}
end
