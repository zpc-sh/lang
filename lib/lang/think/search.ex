defmodule Lang.Think.Search do
  @moduledoc """
  Facade for semantic and similarity search across the codebase.
  """

  alias Lang.Think.Request

  @type params :: %{optional(String.t() | atom()) => any()}

  @spec find_semantic(params) :: {:ok, Request.t()} | {:error, any()}
  def find_semantic(params) when is_map(params) do
    enqueue(:find_semantic, params)
  end

  @spec find_similar(params) :: {:ok, Request.t()} | {:error, any()}
  def find_similar(params) when is_map(params) do
    enqueue(:find_similar, params)
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

