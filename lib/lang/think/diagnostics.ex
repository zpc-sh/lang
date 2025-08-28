defmodule Lang.Think.Diagnostics do
  @moduledoc """
  Facade for diagnostic requests: stack trace to plain-English diagnosis.
  """

  alias Lang.Think.Request

  @type params :: %{optional(String.t() | atom()) => any()}

  @spec diagnose(params) :: {:ok, Request.t()} | {:error, any()}
  def diagnose(params) when is_map(params) do
    Request.create_enqueued(%{
      kind: :diagnose,
      input: Map.get(params, :input) || Map.get(params, "input") || %{},
      user_id: Map.get(params, :user_id) || Map.get(params, "user_id"),
      project_id: Map.get(params, :project_id) || Map.get(params, "project_id"),
      run_id: Map.get(params, :run_id) || Map.get(params, "run_id"),
      metadata: Map.get(params, :metadata) || Map.get(params, "metadata") || %{}
    })
  end
end

