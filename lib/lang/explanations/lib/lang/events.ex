defmodule Lang.Events do
  @moduledoc """
  Event emission helpers that route through Ash resources/notifiers (AshEvents‑style).

  Use this module to emit events so authentication/enrichment layers can hook in uniformly.
  """

  @doc """
  Emit a dev model pipeline event via `Lang.Dev.ModelEvent.log/1`.
  Accepts a map with at least `:event_type` and `:model_id`.
  """
  @spec emit_dev_model_event(map()) :: :ok | {:error, term()}
  def emit_dev_model_event(%{event_type: _t, model_id: _id} = attrs) do
    # Future: enrich with actor/org from AshAuthentication context if available
    case Lang.Dev.ModelEvent.log(attrs) do
      {:ok, _rec} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  def emit_dev_model_event(other), do: {:error, {:invalid_event, other}}
end

