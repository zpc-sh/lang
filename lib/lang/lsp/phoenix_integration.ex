defmodule Lang.LSP.PhoenixIntegration do
  @moduledoc """
  Integration layer between LSP Server and Phoenix features.

  This module demonstrates how the LSP server leverages Phoenix:
  - PubSub for internal message routing and diagnostics distribution
  - Task.Supervisor for concurrent processing
  - Process registry for connection management
  - Telemetry for monitoring and metrics
  """

  alias Phoenix.PubSub
  require Logger

  @pubsub Lang.PubSub

  @doc """
  Broadcasts diagnostics to all interested subscribers (e.g., web UI).
  This allows real-time display of diagnostics in Phoenix LiveView.
  """
  def broadcast_diagnostics(uri, diagnostics) do
    PubSub.broadcast(@pubsub, "lsp:diagnostics", %{
      uri: uri,
      diagnostics: diagnostics,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Broadcasts completion results for caching and analysis.
  """
  def broadcast_completions(uri, position, completions) do
    PubSub.broadcast(@pubsub, "lsp:completions", %{
      uri: uri,
      position: position,
      completions: completions,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Starts an async analysis task using Phoenix's Task.Supervisor.
  """
  def async_analyze(uri, content, callback) do
    Task.Supervisor.start_child(Lang.LSP.TaskSupervisor, fn ->
      format = extract_format_from_uri(uri)

      result = Lang.TextIntelligence.AnalysisEngine.analyze_content(content, format)
      callback.(result)
    end)
  end

  @doc """
  Register a client connection in Phoenix's Registry.
  """
  def register_client(socket, client_info) do
    Registry.register(Lang.LSP.Registry, socket, client_info)
  end

  @doc """
  Get all active LSP client connections.
  """
  def list_clients do
    Registry.select(Lang.LSP.Registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
  end

  @doc """
  Stream large analysis results using Phoenix PubSub.
  """
  def stream_analysis_results(uri, analysis_stream) do
    stream_id = "analysis_#{:erlang.unique_integer([:positive])}"

    Task.start_link(fn ->
      analysis_stream
      |> Stream.chunk_every(10)
      |> Stream.with_index()
      |> Enum.each(fn {chunk, index} ->
        PubSub.broadcast(@pubsub, "lsp:analysis_stream:#{stream_id}", %{
          chunk: chunk,
          index: index,
          uri: uri
        })

        # Rate limiting
        Process.sleep(50)
      end)

      PubSub.broadcast(@pubsub, "lsp:analysis_stream:#{stream_id}", %{
        complete: true,
        uri: uri
      })
    end)

    {:ok, stream_id}
  end

  @doc """
  Monitor LSP server health using Telemetry.
  """
  def report_metrics(event, measurements, metadata \\ %{}) do
    :telemetry.execute(
      [:lang, :lsp, event],
      measurements,
      metadata
    )
  end

  @doc """
  Setup telemetry handlers for LSP metrics.
  """
  def setup_telemetry do
    events = [
      [:lang, :lsp, :request],
      [:lang, :lsp, :response],
      [:lang, :lsp, :connection],
      [:lang, :lsp, :error]
    ]

    :telemetry.attach_many(
      "lang-lsp-metrics",
      events,
      &handle_telemetry_event/4,
      %{}
    )
  end

  defp handle_telemetry_event([:lang, :lsp, :request], measurements, metadata, _config) do
    Logger.info("LSP Request",
      method: metadata.method,
      duration: measurements.duration
    )
  end

  defp handle_telemetry_event([:lang, :lsp, :response], measurements, metadata, _config) do
    Logger.info("LSP Response",
      method: metadata.method,
      size: measurements.size,
      duration: measurements.duration
    )
  end

  defp handle_telemetry_event([:lang, :lsp, :connection], measurements, metadata, _config) do
    Logger.info("LSP Connection",
      action: metadata.action,
      client_count: measurements.client_count
    )
  end

  defp handle_telemetry_event([:lang, :lsp, :error], _measurements, metadata, _config) do
    Logger.error("LSP Error",
      error: metadata.error,
      method: metadata.method
    )
  end

  defp extract_format_from_uri(uri) do
    case Path.extname(uri) do
      ".md" -> "markdown"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      ".py" -> "python"
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      _ -> "text"
    end
  end
end
