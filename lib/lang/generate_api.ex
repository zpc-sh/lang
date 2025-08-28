defmodule Lang.GenerateAPI do
  @moduledoc "Facade over Lang.Generate resources for LSP handlers."

  alias Lang.Generate.{Request, Artifact}
  require Ash.Query

  @spec create_request(map()) :: {:ok, Request.t()} | {:error, term()}
  def create_request(attrs) when is_map(attrs) do
    Request.create(attrs)
  end

  @spec enqueue_request(String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_request(request_id) when is_binary(request_id) do
    %{"request_id" => request_id}
    |> Lang.Generate.Workers.RequestWorker.new(queue: :analysis)
    |> Oban.insert()
  end

  @spec list_artifacts(String.t()) :: {:ok, [Artifact.t()]} | {:error, term()}
  def list_artifacts(request_id) do
    Artifact
    |> Ash.Query.filter(request_id == ^request_id)
    |> Ash.read()
  end
end
