defmodule LangTest do
  use ExUnit.Case, async: true
  doctest Lang

  alias Lang.TextIntelligence.AnalysisEngine
  alias Lang.Conversation.RehearsalEngine
  alias Lang.Stylometrics.AnalysisEngine, as: StyleEngine
  alias Lang.TimeMachine.Core, as: TimeMachine

  describe "Lang.analyze_content/3" do
    test "analyzes markdown content successfully" do
      markdown_content = """
      # Test Document

      This is a test document with some content.

      ## Section 1

      More content here with some **bold** text and [links](http://example.com).
      """

      assert {:ok, result} = Lang.analyze_content(markdown_content, "markdown")
      assert result.format == "markdown"
      assert is_list(result.completions)
      assert is_map(result.analysis)
      assert result.analysis.complexity_score > 0
      assert result.analysis.readability_score > 0
    end

    test "analyzes JavaScript content successfully" do
      js_content = """
      function calculateSum(a, b) {
          return a + b;
      }

      class Calculator {
          constructor() {
              this.result = 0;
          }

          add(value) {
              this.result += value;
              return this;
          }
      }
      """

      assert {:ok, result} = Lang.analyze_content(js_content, "javascript")
      assert result.format == "javascript"
      assert is_list(result.completions)
      assert is_map(result.analysis)
    end

    test "returns error for unsupported format" do
      content = "Some content"
      assert {:error, :unsupported_format} = Lang.analyze_content(content, "unsupported")
    end
  end

  describe "Lang.start_conversation_rehearsal/2" do
    test "starts a job interview rehearsal session" do
      scenario = "job_interview"
      participants = ["candidate", "interviewer"]

      assert {:ok, session} = Lang.start_conversation_rehearsal(scenario, participants)
      assert session.scenario == scenario
      assert session.participants == participants
      assert session.status == :active
      assert is_binary(session.id)
    end

    test "starts a sales call rehearsal session" do
      scenario = "sales_call"
      participants = ["salesperson", "prospect"]

      assert {:ok, session} = Lang.start_conversation_rehearsal(scenario, participants)
      assert session.scenario == scenario
      assert session.participants == participants
    end
  end

  describe "Lang.analyze_writing_style/1" do
    test "analyzes writing style successfully" do
      content = """
      I believe that artificial intelligence represents one of the most
      significant technological advances of our time. The implications
      extend far beyond mere computational efficiency. Furthermore, the
      integration of AI into various sectors will fundamentally transform
      how we approach problem-solving and decision-making processes.
      """

      assert {:ok, analysis} = Lang.analyze_writing_style(content)
      assert is_map(analysis.linguistic_features)
      assert is_map(analysis.syntactic_features)
      assert is_map(analysis.lexical_features)
      assert is_map(analysis.stylistic_features)
      assert is_map(analysis.fingerprint)
      assert analysis.confidence_score > 0
    end

    test "handles short content with lower confidence" do
      short_content = "This is short."

      assert {:ok, analysis} = Lang.analyze_writing_style(short_content)
      assert analysis.confidence_score < 0.5
    end
  end

  describe "Lang.create_timeline/2" do
    test "creates a new timeline successfully" do
      content_id = "doc_123"
      initial_state = %{content: "Initial document content", version: 1}

      assert {:ok, timeline} = Lang.create_timeline(content_id, initial_state)
      assert timeline.content_id == content_id
      assert timeline.current_position == 0
      assert map_size(timeline.states) == 1
      assert map_size(timeline.branches) == 1
    end
  end

  describe "Lang.supported_formats/0" do
    test "returns list of supported formats" do
      formats = Lang.supported_formats()
      assert is_list(formats)
      assert length(formats) > 0

      # Check that key formats are supported
      format_names = Enum.map(formats, & &1.format)
      assert "markdown" in format_names
      assert "javascript" in format_names
      assert "python" in format_names
      assert "json" in format_names
    end
  end

  describe "Lang.health_check/0" do
    test "returns system health status" do
      health = Lang.health_check()
      assert health.status == :ok
      assert is_binary(health.version)
      assert is_map(health.services)

      # Check that core services are tracked
      assert Map.has_key?(health.services, :parser_registry)
      assert Map.has_key?(health.services, :rehearsal_engine)
      assert Map.has_key?(health.services, :lsp_server)
      assert Map.has_key?(health.services, :time_machine)
    end
  end

  describe "integration tests" do
    test "complete workflow: analyze → rehearse → style → timeline" do
      # 1. Analyze content
      content = """
      # Meeting Preparation

      I need to prepare for tomorrow's client meeting. The agenda includes:

      - Project timeline review
      - Budget discussion
      - Next steps planning
      """

      assert {:ok, analysis} = Lang.analyze_content(content, "markdown")
      assert analysis.format == "markdown"

      # 2. Start conversation rehearsal
      assert {:ok, session} =
               Lang.start_conversation_rehearsal("presentation", ["presenter", "client"])

      assert session.scenario == "presentation"

      # 3. Analyze writing style
      assert {:ok, style_analysis} = Lang.analyze_writing_style(content)
      assert style_analysis.confidence_score > 0

      # 4. Create timeline
      assert {:ok, timeline} = Lang.create_timeline("meeting_prep", %{content: content})
      assert timeline.content_id == "meeting_prep"
      assert timeline.current_position == 0
    end

    test "batch content analysis" do
      contents = [
        {"# Header 1\n\nContent 1", "markdown"},
        {"function test() { return 1; }", "javascript"},
        {"{\"key\": \"value\"}", "json"}
      ]

      assert {:ok, results} = AnalysisEngine.batch_analyze(contents)
      assert length(results) == 3

      Enum.each(results, fn result ->
        case result do
          {:ok, analysis} -> assert is_map(analysis)
          {:error, _} -> flunk("Unexpected error in batch analysis")
        end
      end)
    end

    test "conversation rehearsal with multiple turns" do
      # Start session
      assert {:ok, session} =
               Lang.start_conversation_rehearsal("job_interview", ["candidate", "interviewer"])

      # Add first turn
      turn1_data = %{
        "speaker" => "interviewer",
        "message" => "Tell me about yourself.",
        "metadata" => %{}
      }

      assert {:ok, node1} = RehearsalEngine.add_conversation_turn(session.id, turn1_data)
      assert node1.speaker == "interviewer"
      assert is_list(node1.branches)
      assert length(node1.branches) > 0

      # Add response
      turn2_data = %{
        "speaker" => "candidate",
        "message" => "I'm a software engineer with 5 years of experience...",
        "metadata" => %{}
      }

      assert {:ok, node2} = RehearsalEngine.add_conversation_turn(session.id, turn2_data)
      assert node2.speaker == "candidate"

      # Get session analysis
      assert {:ok, session_analysis} = RehearsalEngine.get_conversation_analysis(session.id)
      assert session_analysis.session_id == session.id
      assert session_analysis.conversation_flow.total_turns == 2
    end

    test "stylometric comparison workflow" do
      sample1 = """
      I believe that technology will continue to evolve rapidly.
      The implications are significant and far-reaching.
      """

      sample2 = """
      Technology evolves fast. This has big implications.
      """

      assert {:ok, comparison} = StyleEngine.compare_writing_styles(sample1, sample2)
      assert is_float(comparison.similarity_score)
      assert is_boolean(comparison.likely_same_author)
      assert is_map(comparison.feature_similarities)
    end

    test "time machine branch and merge workflow" do
      # Create initial timeline
      content_id = "branching_doc"
      initial_content = %{text: "Version 1", author: "user1"}

      assert {:ok, timeline} = TimeMachine.create_timeline(content_id, initial_content)

      # Add second state
      version2 = %{text: "Version 2 with changes", author: "user1"}
      assert {:ok, state2} = TimeMachine.add_state(timeline.id, version2)

      # Create branch from first state
      {:ok, updated_timeline} = Lang.TimeMachine.StateManager.get_timeline(timeline.id)
      first_state_id = List.first(Map.keys(updated_timeline.states))

      assert {:ok, branch} =
               TimeMachine.create_branch(timeline.id, first_state_id, "feature_branch")

      assert branch.name == "feature_branch"

      # Add state to branch would require more complex state management
      # This test verifies the basic branching structure works
    end
  end
end
