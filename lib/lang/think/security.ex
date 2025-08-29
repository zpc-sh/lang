defmodule Lang.Think.Security do
  @moduledoc """
  Facade for AI-powered security scans and vulnerability detection.
  """

  alias Lang.Think.Request

  @type params :: %{optional(String.t() | atom()) => any()}

  @spec security_scan(params) :: {:ok, Request.t()} | {:error, any()}
  def security_scan(params) when is_map(params) do
    Request.create_enqueued(%{
      kind: :security_scan,
      input: Map.get(params, :input) || Map.get(params, "input") || %{},
      user_id: Map.get(params, :user_id) || Map.get(params, "user_id"),
      project_id: Map.get(params, :project_id) || Map.get(params, "project_id"),
      run_id: Map.get(params, :run_id) || Map.get(params, "run_id"),
      metadata: Map.get(params, :metadata) || Map.get(params, "metadata") || %{}
    })
  end
end
