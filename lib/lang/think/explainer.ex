defmodule Lang.Think.Explainer do
  @moduledoc """
  Facade for explanation requests.

  Provides helpers for:
  - intent: what the code is trying to accomplish
  - why: business context and rationale
  - how: step-by-step execution explanation

  These helpers enqueue `Lang.Think.Request` jobs via Ash, returning the
  created request for downstream tracking.
  """

  alias Lang.Think.Request

  @type id :: String.t() | nil
  @type params :: %{optional(String.t() | atom()) => any()}

  @spec explain_intent(params) :: {:ok, Request.t()} | {:error, any()}
  def explain_intent(params) when is_map(params) do
    enqueue(:explain_intent, params)
  end

  @spec explain_why(params) :: {:ok, Request.t()} | {:error, any()}
  def explain_why(params) when is_map(params) do
    enqueue(:explain_why, params)
  end

  @spec explain_how(params) :: {:ok, Request.t()} | {:error, any()}
  def explain_how(params) when is_map(params) do
    enqueue(:explain_how, params)
  end

  defp enqueue(kind, params) do
    Request.create_enqueued(%{
      kind: kind,
      input: Map.get(params, :input) || Map.get(params, "input") || %{},
      user_id: Map.get(params, :user_id) || Map.get(params, "user_id"),
      project_id: Map.get(params, :project_id) || Map.get(params, "project_id"),
      run_id: Map.get(params, :run_id) || Map.get(params, "run_id"),
      metadata: Map.get(params, :metadata) || Map.get(params, "metadata") || %{}
    })
  end
end

