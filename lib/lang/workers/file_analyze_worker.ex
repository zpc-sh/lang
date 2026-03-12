defmodule Lang.Workers.FileAnalyzeWorker do
  use Oban.Worker, queue: :analysis, max_attempts: 3
  require Logger

  alias Lang.Analyses.File
  alias Lang.Analyses.Adapters.{Parser, TextIntelligence, Stylometrics}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_id" => file_id} = args}) do
    with {:ok, file} <- File.by_id(file_id),
         {:ok, content} <- fetch_content(file, args),
         {:ok, format} <- Parser.detect(content),
         {:ok, parsed} <- Parser.parse(content, format),
         {:ok, ti} <- TextIntelligence.analyze(content, format: format),
         {:ok, style} <- Stylometrics.compute(content) do
      result = %{parsed: parsed, text_intel: ti, stylometrics: style}
      {:ok, _} = File.complete(file, %{analysis_result: result}, %{processing_time_ms: 0})
      :ok
    else
      {:error, reason} ->
        Logger.error("File analysis failed", file_id: file_id, reason: inspect(reason))

        case File.by_id(file_id) do
          {:ok, file} -> File.fail(file, %{}, %{error_message: inspect(reason)})
          _ -> :ok
        end

        :ok
    end
  end

  defp fetch_content(%{vfs_uri: uri}, _args) when is_binary(uri) do
    case Lang.Storage.VFS.get(uri) do
      {:ok, content} -> {:ok, content}
      {:error, _} -> {:error, :vfs_unavailable}
    end
  end

  defp fetch_content(_file, %{"content" => content}) when is_binary(content), do: {:ok, content}
  defp fetch_content(_file, _), do: {:error, :no_content}
end
