defmodule Lang do
  @moduledoc """
  LANG Universal Text Intelligence Platform

  The main entry point for LANG services including:
  - Universal text parsing and analysis
  - Conversation rehearsal and optimization
  - Stylometric analysis and obfuscation
  - Temporal navigation and replay
  - Language Server Protocol implementation
  """

  alias Lang.TextIntelligence.AnalysisEngine
  alias Lang.Conversation.RehearsalEngine
  alias Lang.Stylometrics.AnalysisEngine, as: StyleEngine
  alias Lang.TimeMachine.Core, as: TimeMachine

  @doc """
  Analyze any structured text content and provide intelligence
  """
  def analyze_content(content, format, options \\ %{}) do
    AnalysisEngine.analyze_content(content, format, options)
  end

  @doc """
  Start a conversation rehearsal session
  """
  def start_conversation_rehearsal(scenario, participants) do
    RehearsalEngine.start_session(scenario, participants)
  end

  @doc """
  Analyze writing style for fingerprinting or obfuscation
  """
  def analyze_writing_style(content) do
    StyleEngine.analyze_writing_style(content)
  end

  @doc """
  Create a temporal timeline for content evolution
  """
  def create_timeline(content_id, initial_state) do
    TimeMachine.create_timeline(content_id, initial_state)
  end

  @doc """
  Get supported text formats
  """
  def supported_formats do
    Lang.TextIntelligence.ParserRegistry.list_supported_formats()
  end

  @doc """
  Get system health status
  """
  def health_check do
    %{
      status: :ok,
      version: Application.spec(:lang, :vsn) |> to_string(),
      timestamp: DateTime.utc_now(),
      services: %{
        parser_registry: service_health(Lang.TextIntelligence.ParserRegistry),
        rehearsal_engine: service_health(Lang.Conversation.RehearsalEngine),
        lsp_server: service_health(Lang.LSP.Server),
        time_machine: service_health(Lang.TimeMachine.StateManager)
      }
    }
  end

  defp service_health(module) do
    case Process.whereis(module) do
      nil -> :not_running
      pid when is_pid(pid) -> :running
    end
  end
end
