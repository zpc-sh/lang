defmodule Lang.Think.Predictor do
  @moduledoc """
  Facade for prediction requests: bug and performance risk prediction.
  """

  alias Lang.Think.Request

  @type params :: %{optional(String.t() | atom()) => any()}

  @spec predict_bugs(params) :: {:ok, Request.t()} | {:error, any()}
  def predict_bugs(params) when is_map(params) do
    enqueue(:predict_bugs, params)
  end

  @spec predict_performance(params) :: {:ok, Request.t()} | {:error, any()}
  def predict_performance(params) when is_map(params) do
    enqueue(:predict_performance, params)
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

