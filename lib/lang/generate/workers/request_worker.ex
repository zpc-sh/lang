defmodule Lang.Generate.Workers.RequestWorker do
  @moduledoc """
  Executes generative requests and emits artifacts (patches/files) with boundaries.
  """

  use Oban.Worker, queue: :analysis, max_attempts: 3
  require Logger

  alias Lang.Generate.{Request, Artifact}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => request_id}}) do
    with {:ok, req} <- Request.by_id(request_id),
         {:ok, _} <- Request.update_status(req, %{}, %{status: :running}) do
      case execute(req) do
        {:ok, artifacts} ->
          Enum.each(artifacts, fn art ->
            _ = Artifact.create(Map.put(art, :request_id, req.id))
          end)

          {:ok, _} = Request.complete(req, %{metadata: %{artifact_count: length(artifacts)}})
          :ok

        {:error, reason} ->
          Logger.error("Generate request failed", request_id: req.id, reason: inspect(reason))
          {:ok, _} = Request.fail(req, %{error_message: to_string(reason), metadata: %{}})
          :ok
      end
    else
      _ -> :ok
    end
  end

  defp execute(%Request{strategy: _strategy, inputs: inputs, boundaries: _bounds}) do
    # Placeholder MVP – emit a no-op patch artifact to demonstrate flow
    path = inputs["path"] || inputs[:path] || "README.md"
    patch = [
      "diff --git a/", path, " b/", path, "
",
      "--- a/", path, "
",
      "+++ b/", path, "
",
      "@@
",
      "-Placeholder
",
      "+Generated placeholder
"
    ] |> IO.iodata_to_binary()

    {:ok,
     [
       %{path: path, language: guess_language(path), change_type: :update, patch: patch, metadata: %{notes: "MVP placeholder"}}
     ]}
  end

  defp guess_language(path) do
    case Path.extname(path) do
      ".ex" -> "elixir"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      ".rs" -> "rust"
      ".py" -> "python"
      ".md" -> "markdown"
      _ -> "text"
    end
  end
end

