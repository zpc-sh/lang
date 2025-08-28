defmodule Lang.ThinkAPI do
  @moduledoc "Thin facade over Lang.Think resources for LSP handlers."

  alias Lang.Think.{Request, Result}
  require Ash.Query

  @spec create_request(map()) :: {:ok, Request.t()} | {:error, term()}
  def create_request(attrs) when is_map(attrs) do
    Request.create(attrs)
  end

  @spec enqueue_request(String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_request(request_id) when is_binary(request_id) do
    %{"request_id" => request_id}
    |> Lang.Think.Workers.RequestWorker.new(queue: :analysis)
    |> Oban.insert()
  end

  @spec latest_result(String.t()) :: {:ok, Result.t() | nil} | {:error, term()}
  def latest_result(request_id) do
    Request
    |> Ash.Query.filter(id == ^request_id)
    |> Ash.Query.load([:id])
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:ok, nil}
      {:ok, _req} ->
        Result
        |> Ash.Query.filter(request_id == ^request_id)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.read_one()
      other -> other
    end
  end
end
