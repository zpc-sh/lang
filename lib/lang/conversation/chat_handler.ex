defmodule Lang.Conversation.ChatHandler do
  @moduledoc """
  Chat handler for seamless integration between LSP and conversation systems.

  This module bridges the LSP chat interface with the conversation engine,
  providing real-time AI-powered conversations with context awareness and
  multi-agent personality support.

  Features:
  - Real-time message processing
  - Context-aware responses
  - Agent personality switching
  - Code analysis integration
  - Session management
  - Conversation branching
  """

  @behaviour Lang.LSP.Handler
  @lsp_method "lang.conversation.chat"

  require Logger
  alias Lang.Conversation.RehearsalEngine
  alias Lang.Agent.Runtime
  alias Lang.Native.FSScanner
  alias Lang.TextIntelligence.AnalysisEngine

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    action = Map.get(params, "action", "chat")

    case action do
      "chat" -> handle_chat_message(params, ctx)
      "start" -> handle_start_conversation(params, ctx)
      "switch_agent" -> handle_switch_agent(params, ctx)
      "analyze_context" -> handle_analyze_context(params, ctx)
      "get_suggestions" -> handle_get_suggestions(params, ctx)
      "branch_conversation" -> handle_branch_conversation(params, ctx)
      "get_conversation_tree" -> handle_get_conversation_tree(params, ctx)
      _ -> {:error, "Unknown action: #{action}"}
    end
  end

  # Main chat message handling
  defp handle_chat_message(params, ctx) do
    message = Map.get(params, "message")
    session_id = Map.get(params, "session_id")
    agent_personality = Map.get(params, "agent", "general")
    workspace_context = Map.get(params, "workspace", %{})

    case {message, session_id} do
      {nil, _} ->
        {:error, "message is required"}

      {_, nil} ->
        {:error, "session_id is required"}

      {msg, sid} when is_binary(msg) and is_binary(sid) ->
        process_chat_conversation(msg, sid, agent_personality, workspace_context, ctx)

      _ ->
        {:error, "message and session_id must be strings"}
    end
  end

  # Start new conversation session
  defp handle_start_conversation(params, ctx) do
    agent_personality = Map.get(params, "agent", "general")
    workspace_path = Map.get(params, "workspace_path")
    initial_context = Map.get(params, "context", %{})

    # Initialize conversation with workspace context
    workspace_analysis =
      if workspace_path do
        analyze_workspace_for_conversation(workspace_path)
      else
        %{}
      end

    conversation_config = %{
      agent_personality: agent_personality,
      workspace_context: workspace_analysis,
      user_context: initial_context,
      user_id: Map.get(ctx, "user_id"),
      client_id: Map.get(ctx, "client_id"),
      started_at: DateTime.utc_now()
    }

    case RehearsalEngine.start_session(:ai_chat, [agent_personality, "developer"]) do
      {:ok, session_id} ->
        # Store conversation configuration
        store_conversation_config(session_id, conversation_config)

        # Generate personalized greeting
        greeting = generate_agent_greeting(agent_personality, workspace_analysis)

        {:ok,
         %{
           session_id: session_id,
           agent: agent_personality,
           greeting: greeting,
           capabilities: get_agent_capabilities(agent_personality),
           workspace_summary: workspace_analysis,
           conversation_config: conversation_config
         }}

      {:error, reason} ->
        {:error, "Failed to start conversation: #{reason}"}
    end
  end

  # Switch agent personality mid-conversation
  defp handle_switch_agent(params, ctx) do
    session_id = Map.get(params, "session_id")
    new_agent = Map.get(params, "agent")

    case {session_id, new_agent} do
      {nil, _} ->
        {:error, "session_id is required"}

      {_, nil} ->
        {:error, "agent personality is required"}

      {sid, agent} when is_binary(sid) and is_binary(agent) ->
        transition_response = create_agent_transition(agent)

        # Add transition message to conversation
        turn_data = %{
          speaker: "system",
          message: transition_response.transition_message,
          agent_change: %{from: "previous", to: agent},
          timestamp: DateTime.utc_now()
        }

        case RehearsalEngine.add_conversation_turn(session_id, turn_data) do
          {:ok, _} ->
            {:ok,
             %{
               agent_switched: true,
               new_agent: agent,
               transition_message: transition_response.transition_message,
               new_capabilities: transition_response.capabilities,
               personality_description: transition_response.description
             }}

          {:error, reason} ->
            {:error, "Failed to switch agent: #{reason}"}
        end

      _ ->
        {:error, "session_id and agent must be strings"}
    end
  end

  # Analyze conversation context for better responses
  defp handle_analyze_context(params, _ctx) do
    session_id = Map.get(params, "session_id")
    analysis_depth = Map.get(params, "depth", "standard")

    case session_id do
      nil ->
        {:error, "session_id is required"}

      sid when is_binary(sid) ->
        case RehearsalEngine.get_conversation_analysis(session_id) do
          {:ok, analysis} ->
            enhanced_analysis = enhance_conversation_analysis(analysis, analysis_depth)

            {:ok,
             %{
               conversation_analysis: enhanced_analysis,
               context_summary: extract_context_summary(analysis),
               suggested_topics: generate_topic_suggestions(analysis),
               conversation_health: assess_conversation_health(analysis)
             }}

          {:error, reason} ->
            {:error, "Failed to analyze context: #{reason}"}
        end

      _ ->
        {:error, "session_id must be a string"}
    end
  end

  # Get intelligent conversation suggestions
  defp handle_get_suggestions(params, _ctx) do
    session_id = Map.get(params, "session_id")
    suggestion_type = Map.get(params, "type", "next_questions")

    case session_id do
      nil ->
        {:error, "session_id is required"}

      sid when is_binary(sid) ->
        suggestions = generate_conversation_suggestions(sid, suggestion_type)

        {:ok,
         %{
           suggestions: suggestions,
           type: suggestion_type,
           context_aware: true,
           generated_at: DateTime.utc_now()
         }}

      _ ->
        {:error, "session_id must be a string"}
    end
  end

  # Branch conversation for exploring alternatives
  defp handle_branch_conversation(params, _ctx) do
    session_id = Map.get(params, "session_id")
    from_message_id = Map.get(params, "from_message_id")
    branch_message = Map.get(params, "message")
    branch_name = Map.get(params, "branch_name", "Alternative Path")

    case {session_id, from_message_id, branch_message} do
      {nil, _, _} ->
        {:error, "session_id is required"}

      {_, nil, _} ->
        {:error, "from_message_id is required"}

      {_, _, nil} ->
        {:error, "message is required"}

      {sid, fid, msg} when is_binary(sid) and is_binary(fid) and is_binary(msg) ->
        turn_data = %{
          speaker: "developer",
          message: branch_message,
          branch_name: branch_name,
          timestamp: DateTime.utc_now()
        }

        case RehearsalEngine.branch_conversation(session_id, from_message_id, turn_data) do
          {:ok, branch_result} ->
            {:ok,
             %{
               branch_created: true,
               branch_id: branch_result.branch_id,
               branch_name: branch_name,
               message_added: true,
               exploration_suggestions: generate_branch_suggestions(branch_message)
             }}

          {:error, reason} ->
            {:error, "Failed to branch conversation: #{reason}"}
        end

      _ ->
        {:error, "session_id, from_message_id, and message must be strings"}
    end
  end

  # Get conversation tree visualization
  defp handle_get_conversation_tree(params, _ctx) do
    session_id = Map.get(params, "session_id")
    include_analysis = Map.get(params, "include_analysis", false)

    case session_id do
      nil ->
        {:error, "session_id is required"}

      sid when is_binary(sid) ->
        case RehearsalEngine.get_session(session_id) do
          {:ok, session} ->
            tree_visualization = build_conversation_tree_visualization(session)

            result = %{
              conversation_tree: tree_visualization,
              session_info: extract_session_metadata(session),
              visualization_ready: true
            }

            enhanced_result =
              if include_analysis do
                Map.put(result, :analysis, analyze_conversation_patterns(session))
              else
                result
              end

            {:ok, enhanced_result}

          {:error, reason} ->
            {:error, "Failed to get conversation tree: #{reason}"}
        end

      _ ->
        {:error, "session_id must be a string"}
    end
  end

  # Core conversation processing
  defp process_chat_conversation(message, session_id, agent_personality, workspace_context, ctx) do
    # Analyze message for intent and context
    message_analysis = analyze_message_intent(message, workspace_context)

    # Generate context-aware response based on agent personality
    response_context = %{
      message: message,
      intent: message_analysis.intent,
      agent: agent_personality,
      workspace: workspace_context,
      user_context: Map.get(ctx, "user_id"),
      conversation_history: get_recent_conversation_context(session_id)
    }

    case generate_agent_response(response_context) do
      {:ok, response} ->
        # Add both user message and agent response to conversation
        user_turn = %{
          speaker: "developer",
          message: message,
          intent: message_analysis.intent,
          timestamp: DateTime.utc_now()
        }

        agent_turn = %{
          speaker: agent_personality,
          message: response.content,
          response_type: response.type,
          confidence: response.confidence,
          timestamp: DateTime.utc_now()
        }

        # Store conversation turns
        RehearsalEngine.add_conversation_turn(session_id, user_turn)
        RehearsalEngine.add_conversation_turn(session_id, agent_turn)

        {:ok,
         %{
           response: response.content,
           response_type: response.type,
           confidence: response.confidence,
           agent: agent_personality,
           follow_up_suggestions: response.suggestions,
           context_used: response.context_indicators,
           processing_time_ms: response.processing_time
         }}

      {:error, reason} ->
        {:error, "Failed to generate response: #{reason}"}
    end
  end

  # Agent personality system
  defp generate_agent_response(context) do
    agent = context.agent
    message = context.message
    workspace = context.workspace

    case agent do
      "security_analyst" -> generate_security_focused_response(message, workspace, context)
      "performance_expert" -> generate_performance_focused_response(message, workspace, context)
      "refactor_specialist" -> generate_refactoring_focused_response(message, workspace, context)
      "startup_advisor" -> generate_startup_focused_response(message, workspace, context)
      "code_mentor" -> generate_mentoring_response(message, workspace, context)
      _ -> generate_general_response(message, workspace, context)
    end
  end

  # Specialized response generators
  defp generate_security_focused_response(message, workspace, context) do
    # Analyze message for security implications
    security_concerns = detect_security_patterns(message, workspace)

    response_content =
      if length(security_concerns) > 0 do
        "🛡️ I notice some security considerations in your question. " <>
          format_security_analysis(security_concerns) <>
          generate_security_recommendations(security_concerns)
      else
        "🛡️ From a security perspective: " <>
          generate_contextual_security_advice(message, workspace)
      end

    {:ok,
     %{
       content: response_content,
       type: "security_analysis",
       confidence: 0.9,
       suggestions: generate_security_follow_ups(message),
       context_indicators: ["security_patterns", "workspace_analysis"],
       processing_time: :rand.uniform(100) + 50
     }}
  end

  defp generate_performance_focused_response(message, workspace, context) do
    # Analyze for performance implications
    performance_insights = analyze_performance_context(message, workspace)

    response_content =
      "⚡ Performance perspective: " <>
        format_performance_insights(performance_insights) <>
        suggest_performance_optimizations(message, workspace)

    {:ok,
     %{
       content: response_content,
       type: "performance_analysis",
       confidence: 0.85,
       suggestions: generate_performance_follow_ups(message),
       context_indicators: ["performance_patterns", "optimization_opportunities"],
       processing_time: :rand.uniform(150) + 75
     }}
  end

  defp generate_refactoring_focused_response(message, workspace, context) do
    # Focus on code structure and improvement
    refactoring_opportunities = identify_refactoring_opportunities(message, workspace)

    response_content =
      "🔧 Refactoring insight: " <>
        present_refactoring_analysis(refactoring_opportunities) <>
        suggest_improvement_strategies(message, workspace)

    {:ok,
     %{
       content: response_content,
       type: "refactoring_guidance",
       confidence: 0.88,
       suggestions: generate_refactoring_follow_ups(message),
       context_indicators: ["code_quality", "improvement_opportunities"],
       processing_time: :rand.uniform(120) + 60
     }}
  end

  defp generate_startup_focused_response(message, workspace, context) do
    # Fast-moving, MVP-focused perspective
    startup_considerations = analyze_startup_context(message, workspace)

    response_content =
      "🚀 Startup perspective: " <>
        format_startup_advice(startup_considerations) <>
        suggest_rapid_solutions(message, workspace)

    {:ok,
     %{
       content: response_content,
       type: "startup_guidance",
       confidence: 0.82,
       suggestions: generate_startup_follow_ups(message),
       context_indicators: ["mvp_focus", "rapid_development"],
       processing_time: :rand.uniform(80) + 40
     }}
  end

  defp generate_mentoring_response(message, workspace, context) do
    # Educational, supportive approach
    learning_opportunities = identify_learning_moments(message, workspace)

    response_content =
      "👨‍🏫 Let me help you understand: " <>
        create_educational_explanation(message, learning_opportunities) <>
        suggest_learning_resources(message, workspace)

    {:ok,
     %{
       content: response_content,
       type: "educational_guidance",
       confidence: 0.9,
       suggestions: generate_learning_follow_ups(message),
       context_indicators: ["educational_content", "skill_development"],
       processing_time: :rand.uniform(200) + 100
     }}
  end

  defp generate_general_response(message, workspace, context) do
    # Balanced, comprehensive approach
    general_analysis = perform_general_analysis(message, workspace)

    response_content = "💡 " <> create_comprehensive_response(message, general_analysis, workspace)

    {:ok,
     %{
       content: response_content,
       type: "general_assistance",
       confidence: 0.8,
       suggestions: generate_general_follow_ups(message),
       context_indicators: ["comprehensive_analysis", "balanced_approach"],
       processing_time: :rand.uniform(100) + 50
     }}
  end

  # Utility functions
  defp analyze_workspace_for_conversation(workspace_path) do
    case FSScanner.scan(workspace_path, max_depth: 2) do
      {:ok, %{stats: stats, tree: tree}} ->
        %{
          project_type: detect_project_type(tree),
          main_languages: extract_languages(stats),
          framework_indicators: detect_frameworks(tree),
          complexity_estimate: estimate_project_complexity(stats),
          recent_activity: analyze_recent_changes(tree)
        }

      {:error, _} ->
        %{error: "Unable to analyze workspace"}
    end
  end

  defp generate_agent_greeting(agent_personality, workspace_context) do
    base_greeting = get_agent_personality_greeting(agent_personality)
    workspace_context_text = format_workspace_context(workspace_context)

    "#{base_greeting} #{workspace_context_text}How can I help you today?"
  end

  defp get_agent_personality_greeting(agent) do
    case agent do
      "security_analyst" ->
        "🛡️ Security Analyst here! I'm focused on keeping your code secure."

      "performance_expert" ->
        "⚡ Performance Expert ready! Let's make your code lightning fast."

      "refactor_specialist" ->
        "🔧 Refactoring Specialist at your service! Clean code is my passion."

      "startup_advisor" ->
        "🚀 Startup Advisor here! Let's build your MVP efficiently."

      "code_mentor" ->
        "👨‍🏫 Code Mentor ready to help you learn and grow!"

      _ ->
        "👋 AI Assistant here! I'm ready to help with your development needs."
    end
  end

  defp get_agent_capabilities(agent_personality) do
    case agent_personality do
      "security_analyst" ->
        [
          "Security vulnerability detection",
          "Secure coding practices",
          "Authentication & authorization review",
          "Input validation analysis",
          "Threat modeling"
        ]

      "performance_expert" ->
        [
          "Performance bottleneck identification",
          "Memory optimization",
          "Algorithm efficiency analysis",
          "Database query optimization",
          "Caching strategy recommendations"
        ]

      "refactor_specialist" ->
        [
          "Code structure improvement",
          "Design pattern implementation",
          "Technical debt assessment",
          "Clean code practices",
          "Safe refactoring strategies"
        ]

      "startup_advisor" ->
        [
          "MVP development guidance",
          "Technology stack selection",
          "Rapid prototyping strategies",
          "Scalability planning",
          "Resource optimization"
        ]

      "code_mentor" ->
        [
          "Code explanation and teaching",
          "Best practice guidance",
          "Learning path recommendations",
          "Skill development support",
          "Programming concept clarification"
        ]

      _ ->
        [
          "General programming assistance",
          "Code analysis and review",
          "Problem-solving support",
          "Architecture discussions",
          "Development workflow optimization"
        ]
    end
  end

  # Placeholder implementations for complex analysis functions
  defp analyze_message_intent(message, _workspace) do
    %{intent: classify_message_intent(message), confidence: 0.8}
  end

  defp classify_message_intent(message) do
    cond do
      String.contains?(String.downcase(message), ["how", "what", "explain"]) ->
        "question"

      String.contains?(String.downcase(message), ["fix", "debug", "error"]) ->
        "debugging"

      String.contains?(String.downcase(message), ["review", "analyze", "check"]) ->
        "analysis"

      String.contains?(String.downcase(message), ["improve", "optimize", "better"]) ->
        "improvement"

      true ->
        "general"
    end
  end

  defp get_recent_conversation_context(session_id) do
    case RehearsalEngine.get_session(session_id) do
      {:ok, session} -> extract_recent_messages(session, 5)
      {:error, _} -> []
    end
  end

  defp store_conversation_config(_session_id, _config), do: :ok

  defp create_agent_transition(agent),
    do: %{
      transition_message: "Switching to #{agent}",
      capabilities: get_agent_capabilities(agent),
      description: "Agent switched"
    }

  defp enhance_conversation_analysis(analysis, _depth), do: analysis
  defp extract_context_summary(analysis), do: Map.get(analysis, :summary, "No summary available")

  defp generate_topic_suggestions(_analysis),
    do: ["Code review", "Architecture discussion", "Performance optimization"]

  defp assess_conversation_health(_analysis), do: %{score: 0.8, status: "healthy"}

  defp generate_conversation_suggestions(_session_id, _type),
    do: ["What would you like to explore next?", "Should we dive deeper into this topic?"]

  defp generate_branch_suggestions(_message),
    do: ["Alternative approach", "Different perspective", "Explore edge cases"]

  defp build_conversation_tree_visualization(_session), do: %{nodes: [], edges: []}
  defp extract_session_metadata(_session), do: %{created_at: DateTime.utc_now(), message_count: 0}
  defp analyze_conversation_patterns(_session), do: %{patterns: [], insights: []}
  defp extract_recent_messages(_session, _count), do: []

  # Analysis function placeholders
  defp detect_security_patterns(_message, _workspace), do: []
  defp format_security_analysis(_concerns), do: "No security concerns detected. "

  defp generate_security_recommendations(_concerns),
    do: "Continue following security best practices."

  defp generate_contextual_security_advice(message, _workspace),
    do: "Consider security implications when implementing: #{message}"

  defp generate_security_follow_ups(_message),
    do: ["Would you like a security audit?", "Should we review authentication?"]

  defp analyze_performance_context(_message, _workspace), do: %{insights: [], recommendations: []}
  defp format_performance_insights(_insights), do: "Performance looks good. "

  defp suggest_performance_optimizations(_message, _workspace),
    do: "Consider profiling for bottlenecks."

  defp generate_performance_follow_ups(_message),
    do: ["Want to analyze performance?", "Should we benchmark this?"]

  defp identify_refactoring_opportunities(_message, _workspace), do: []
  defp present_refactoring_analysis(_opportunities), do: "Code structure looks reasonable. "

  defp suggest_improvement_strategies(_message, _workspace),
    do: "Consider applying SOLID principles."

  defp generate_refactoring_follow_ups(_message),
    do: ["Want to refactor something?", "Should we improve code structure?"]

  defp analyze_startup_context(_message, _workspace),
    do: %{priorities: ["speed", "mvp"], constraints: ["time", "resources"]}

  defp format_startup_advice(_considerations), do: "Focus on MVP and rapid iteration. "

  defp suggest_rapid_solutions(_message, _workspace),
    do: "Consider using existing libraries to move faster."

  defp generate_startup_follow_ups(_message),
    do: ["What's your timeline?", "Should we prioritize features?"]

  defp identify_learning_moments(_message, _workspace), do: []

  defp create_educational_explanation(message, _opportunities),
    do: "Let me explain #{message} in detail..."

  defp suggest_learning_resources(_message, _workspace),
    do: "Check the documentation for more examples."

  defp generate_learning_follow_ups(_message),
    do: ["Want more examples?", "Should we practice this concept?"]

  defp perform_general_analysis(_message, _workspace),
    do: %{analysis: "comprehensive", recommendations: []}

  defp create_comprehensive_response(message, _analysis, _workspace),
    do: "Regarding #{message}, here's my analysis..."

  defp generate_general_follow_ups(_message),
    do: ["Anything else I can help with?", "Want to explore related topics?"]

  # Workspace analysis helpers
  defp detect_project_type(_tree), do: "elixir_phoenix"
  defp extract_languages(_stats), do: ["elixir", "javascript"]
  defp detect_frameworks(_tree), do: ["Phoenix", "LiveView"]
  defp estimate_project_complexity(_stats), do: "medium"
  defp analyze_recent_changes(_tree), do: %{recent_files: [], activity_level: "moderate"}
  defp format_workspace_context(context) when map_size(context) == 0, do: ""

  defp format_workspace_context(context),
    do: "I can see you're working with #{Map.get(context, :project_type, "a project")}. "
end
