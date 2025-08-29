defmodule Lang.Think.Tracer do
  @moduledoc """
  Facade for tracing data/control flow across files.
  """

  alias Lang.Think.Request

  @type params :: %{optional(String.t() | atom()) => any()}

  @spec trace_flow(params) :: {:ok, Request.t()} | {:error, any()}
  def trace_flow(params) when is_map(params) do
    Request.create_enqueued(%{
      kind: :trace_flow,
      input: Map.get(params, :input) || Map.get(params, "input") || %{},
      user_id: Map.get(params, :user_id) || Map.get(params, "user_id"),
      project_id: Map.get(params, :project_id) || Map.get(params, "project_id"),
      run_id: Map.get(params, :run_id) || Map.get(params, "run_id"),
      metadata: Map.get(params, :metadata) || Map.get(params, "metadata") || %{}
    })
  end
end
