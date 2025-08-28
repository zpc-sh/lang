defmodule Lang.Think.Workers.RequestWorker do
  @moduledoc """
  Executes cognitive requests (explain, find, trace) and stores results.
  """

  use Oban.Worker, queue: :analysis, max_attempts: 3
  require Logger

  alias Lang.Think.{Request, Result}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => request_id}}) do
    with {:ok, req} <- Request.by_id(request_id),
         {:ok, _} <- Request.update_status(req, %{}, %{status: :running}) do
      case execute(req) do
        {:ok, output} ->
          {:ok, _} =
            Result.create(%{
              request_id: req.id,
              summary: output[:summary],
              details: output[:details] || %{},
              artifacts: output[:artifacts] || [],
              confidence_score: output[:confidence_score],
              metrics: output[:metrics] || %{},
              completed_at: DateTime.utc_now()
            })

          {:ok, _} = Request.complete(req, %{metadata: %{}})
          :ok

        {:error, reason} ->
          Logger.error("Think request failed", request_id: req.id, reason: inspect(reason))
          {:ok, _} = Request.fail(req, %{error_message: to_string(reason), metadata: %{}})
          :ok
      end
    else
      _ -> :ok
    end
  end

  defp execute(%Request{kind: kind, input: input}) do
    # Placeholder execution logic; plug in PerfEngine/Analysis as we flesh out handlers
    {:ok,
     %{
       summary: "#{kind} processed",
       details: %{input: input, notes: "MVP placeholder"},
       confidence_score: Decimal.new("0.5"),
       metrics: %{processing_time_ms: 0}
     }}
  end
end

