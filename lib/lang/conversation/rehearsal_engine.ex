defmodule Lang.Conversation.RehearsalEngine do
  @moduledoc """
  Engine for conversation rehearsal and branching replay
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_session(scenario, participants) do
    session_data = %{
      id: generate_session_id(),
      scenario: scenario,
      participants: participants,
      conversation_tree: %{
        nodes: [],
        current_position: nil,
        branch_history: []
      },
      created_at: DateTime.utc_now(),
      status: :active
    }

    GenServer.call(__MODULE__, {:start_session, session_data})
  end

  def add_conversation_turn(session_id, turn_data) do
    GenServer.call(__MODULE__, {:add_turn, session_id, turn_data})
  end

  def get_session(session_id) do
    GenServer.call(__MODULE__, {:get_session, session_id})
  end

  def list_sessions(filters \\ %{}) do
    GenServer.call(__MODULE__, {:list_sessions, filters})
  end

  def branch_conversation(session_id, from_node_id, new_turn_data) do
    GenServer.call(__MODULE__, {:branch_conversation, session_id, from_node_id, new_turn_data})
  end

  def navigate_to_node(session_id, node_id) do
    GenServer.call(__MODULE__, {:navigate_to_node, session_id, node_id})
  end

  def get_conversation_analysis(session_id) do
    GenServer.call(__MODULE__, {:analyze_conversation, session_id})
  end

  def end_session(session_id) do
    GenServer.call(__MODULE__, {:end_session, session_id})
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Conversation Rehearsal Engine")
    {:ok, %{sessions: %{}, stats: %{total_sessions: 0, active_sessions: 0}}}
  end

  @impl true
  def handle_call({:start_session, session_data}, _from, state) do
    Logger.info("Starting rehearsal session", scenario: session_data.scenario)

    sessions = Map.put(state.sessions, session_data.id, session_data)

    stats = %{
      state.stats
      | total_sessions: state.stats.total_sessions + 1,
        active_sessions: state.stats.active_sessions + 1
    }

    {:reply, {:ok, session_data}, %{state | sessions: sessions, stats: stats}}
  end

  @impl true
  def handle_call({:add_turn, session_id, turn_data}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      %{status: :ended} ->
        {:reply, {:error, :session_ended}, state}

      session ->
        node = %{
          id: generate_node_id(),
          timestamp: DateTime.utc_now(),
          content: turn_data,
          speaker: Map.get(turn_data, "speaker", "unknown"),
          message: Map.get(turn_data, "message", Map.get(turn_data, "content", "")),
          metadata: Map.get(turn_data, "metadata", %{}),
          branches: generate_response_branches(turn_data, session.scenario),
          parent_id: session.conversation_tree.current_position
        }

        updated_tree = add_node_to_tree(session.conversation_tree, node)
        updated_session = %{session | conversation_tree: updated_tree}

        sessions = Map.put(state.sessions, session_id, updated_session)
        {:reply, {:ok, node}, %{state | sessions: sessions}}
    end
  end

  @impl true
  def handle_call({:get_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> {:reply, {:error, :session_not_found}, state}
      session -> {:reply, {:ok, session}, state}
    end
  end

  @impl true
  def handle_call({:list_sessions, filters}, _from, state) do
    sessions =
      state.sessions
      |> Map.values()
      |> apply_session_filters(filters)
      |> Enum.map(&session_summary/1)

    {:reply, {:ok, sessions}, state}
  end

  @impl true
  def handle_call({:branch_conversation, session_id, from_node_id, new_turn_data}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session ->
        case find_node_in_tree(session.conversation_tree, from_node_id) do
          nil ->
            {:reply, {:error, :node_not_found}, state}

          _node ->
            branch_id = generate_branch_id()

            new_node = %{
              id: generate_node_id(),
              timestamp: DateTime.utc_now(),
              content: new_turn_data,
              speaker: Map.get(new_turn_data, "speaker", "unknown"),
              message: Map.get(new_turn_data, "message", Map.get(new_turn_data, "content", "")),
              metadata: Map.get(new_turn_data, "metadata", %{}),
              branches: generate_response_branches(new_turn_data, session.scenario),
              parent_id: from_node_id,
              branch_id: branch_id
            }

            updated_tree =
              add_branch_to_tree(session.conversation_tree, new_node, from_node_id, branch_id)

            updated_session = %{session | conversation_tree: updated_tree}

            sessions = Map.put(state.sessions, session_id, updated_session)
            {:reply, {:ok, new_node}, %{state | sessions: sessions}}
        end
    end
  end

  @impl true
  def handle_call({:navigate_to_node, session_id, node_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session ->
        case find_node_in_tree(session.conversation_tree, node_id) do
          nil ->
            {:reply, {:error, :node_not_found}, state}

          _node ->
            updated_tree = %{session.conversation_tree | current_position: node_id}
            updated_session = %{session | conversation_tree: updated_tree}

            sessions = Map.put(state.sessions, session_id, updated_session)
            {:reply, {:ok, :navigated}, %{state | sessions: sessions}}
        end
    end
  end

  @impl true
  def handle_call({:analyze_conversation, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session ->
        analysis = analyze_conversation_session(session)
        {:reply, {:ok, analysis}, state}
    end
  end

  @impl true
  def handle_call({:end_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session ->
        updated_session = %{session | status: :ended, ended_at: DateTime.utc_now()}
        sessions = Map.put(state.sessions, session_id, updated_session)
        stats = %{state.stats | active_sessions: state.stats.active_sessions - 1}

        {:reply, {:ok, :session_ended}, %{state | sessions: sessions, stats: stats}}
    end
  end

  # Private helper functions

  defp generate_response_branches(turn_data, scenario) do
    message = Map.get(turn_data, "message", Map.get(turn_data, "content", ""))

    case scenario do
      "job_interview" -> generate_interview_branches(message)
      "sales_call" -> generate_sales_branches(message)
      "customer_support" -> generate_support_branches(message)
      "negotiation" -> generate_negotiation_branches(message)
      "presentation" -> generate_presentation_branches(message)
      _ -> generate_default_branches(message)
    end
  end

  defp generate_interview_branches(message) do
    base_sentiment = analyze_message_sentiment(message)

    [
      %{
        id: "confident_approach",
        response_text: "I'm confident in my ability to handle this challenge because...",
        strategy: "confident_communication",
        predicted_outcome: %{
          success_probability: 0.75,
          engagement_level: 0.8,
          perceived_competence: 0.85
        },
        tone: "confident",
        follow_up_questions: [
          "Can you give me a specific example?",
          "How would you handle setbacks?"
        ]
      },
      %{
        id: "detail_oriented_approach",
        response_text: "Let me walk you through the specific steps I would take...",
        strategy: "detailed_explanation",
        predicted_outcome: %{
          success_probability: 0.70,
          engagement_level: 0.75,
          perceived_competence: 0.80
        },
        tone: "analytical",
        follow_up_questions: ["What if the timeline changes?", "How do you prioritize tasks?"]
      },
      %{
        id: "collaborative_approach",
        response_text: "I'd love to collaborate with the team on this. My approach would be...",
        strategy: "team_oriented",
        predicted_outcome: %{
          success_probability: 0.80,
          engagement_level: 0.85,
          perceived_competence: 0.75
        },
        tone: "collaborative",
        follow_up_questions: [
          "How do you handle disagreements?",
          "Tell me about a team challenge you faced."
        ]
      }
    ]
  end

  defp generate_sales_branches(message) do
    [
      %{
        id: "consultative_approach",
        response_text:
          "Help me understand your current challenges so I can provide the best solution...",
        strategy: "consultative_selling",
        predicted_outcome: %{
          success_probability: 0.85,
          engagement_level: 0.90,
          trust_level: 0.80
        },
        tone: "consultative",
        next_steps: ["discovery_questions", "needs_assessment"]
      },
      %{
        id: "value_proposition",
        response_text: "Here's exactly how our solution can benefit your organization...",
        strategy: "value_focused",
        predicted_outcome: %{
          success_probability: 0.70,
          engagement_level: 0.75,
          trust_level: 0.70
        },
        tone: "persuasive",
        next_steps: ["demo_request", "roi_discussion"]
      },
      %{
        id: "social_proof",
        response_text: "Companies similar to yours have seen remarkable results. Let me share...",
        strategy: "credibility_building",
        predicted_outcome: %{
          success_probability: 0.75,
          engagement_level: 0.80,
          trust_level: 0.85
        },
        tone: "credible",
        next_steps: ["case_study_review", "reference_call"]
      }
    ]
  end

  defp generate_support_branches(message) do
    [
      %{
        id: "empathetic_resolution",
        response_text:
          "I understand how frustrating this must be. Let me help you resolve this immediately...",
        strategy: "empathy_first",
        predicted_outcome: %{
          success_probability: 0.80,
          satisfaction_level: 0.85,
          resolution_speed: 0.70
        },
        tone: "empathetic"
      },
      %{
        id: "technical_deep_dive",
        response_text: "Let's troubleshoot this step by step. First, can you...",
        strategy: "systematic_resolution",
        predicted_outcome: %{
          success_probability: 0.85,
          satisfaction_level: 0.75,
          resolution_speed: 0.80
        },
        tone: "technical"
      }
    ]
  end

  defp generate_negotiation_branches(message) do
    [
      %{
        id: "win_win_approach",
        response_text: "I want to find a solution that works for both of us. What if we...",
        strategy: "collaborative_negotiation",
        predicted_outcome: %{
          success_probability: 0.85,
          relationship_preservation: 0.90,
          value_creation: 0.80
        },
        tone: "collaborative"
      },
      %{
        id: "firm_boundaries",
        response_text: "I appreciate your position, but here's what we can realistically do...",
        strategy: "principled_negotiation",
        predicted_outcome: %{
          success_probability: 0.70,
          relationship_preservation: 0.75,
          value_creation: 0.70
        },
        tone: "firm_but_fair"
      }
    ]
  end

  defp generate_presentation_branches(message) do
    [
      %{
        id: "storytelling_approach",
        response_text: "Let me tell you a story that illustrates this perfectly...",
        strategy: "narrative_engagement",
        predicted_outcome: %{
          success_probability: 0.80,
          audience_engagement: 0.90,
          message_retention: 0.85
        },
        tone: "engaging"
      },
      %{
        id: "data_driven",
        response_text: "The data clearly shows that...",
        strategy: "evidence_based",
        predicted_outcome: %{
          success_probability: 0.75,
          audience_engagement: 0.70,
          message_retention: 0.80
        },
        tone: "analytical"
      }
    ]
  end

  defp generate_default_branches(message) do
    sentiment = analyze_message_sentiment(message)

    base_branches = [
      %{
        id: "empathetic_response",
        response_text: "I understand how you feel. Let me address that...",
        strategy: "empathetic_communication",
        predicted_outcome: %{
          success_probability: 0.70,
          engagement_level: 0.80,
          emotional_connection: 0.85
        },
        tone: "empathetic"
      },
      %{
        id: "direct_response",
        response_text: "Here's my direct response to that...",
        strategy: "straightforward_communication",
        predicted_outcome: %{
          success_probability: 0.65,
          engagement_level: 0.70,
          clarity_level: 0.90
        },
        tone: "direct"
      }
    ]

    # Add sentiment-specific branches
    case sentiment do
      :positive ->
        base_branches ++
          [
            %{
              id: "build_on_positivity",
              response_text: "I'm glad you feel that way! Building on that...",
              strategy: "positive_momentum",
              predicted_outcome: %{success_probability: 0.85, engagement_level: 0.90},
              tone: "enthusiastic"
            }
          ]

      :negative ->
        base_branches ++
          [
            %{
              id: "address_concerns",
              response_text: "I hear your concerns. Let's work through them together...",
              strategy: "concern_resolution",
              predicted_outcome: %{success_probability: 0.75, engagement_level: 0.80},
              tone: "reassuring"
            }
          ]

      _ ->
        base_branches
    end
  end

  defp add_node_to_tree(tree, node) do
    %{
      tree
      | nodes: [node | tree.nodes],
        current_position: node.id,
        branch_history: [node.id | tree.branch_history]
    }
  end

  defp add_branch_to_tree(tree, node, _from_node_id, branch_id) do
    updated_branch_history = [branch_id | tree.branch_history]

    %{
      tree
      | nodes: [node | tree.nodes],
        current_position: node.id,
        branch_history: updated_branch_history
    }
  end

  defp find_node_in_tree(tree, node_id) do
    Enum.find(tree.nodes, fn node -> node.id == node_id end)
  end

  defp apply_session_filters(sessions, filters) do
    sessions
    |> filter_by_scenario(Map.get(filters, "scenario"))
    |> filter_by_status(Map.get(filters, "status"))
    |> filter_by_date_range(Map.get(filters, "date_from"), Map.get(filters, "date_to"))
  end

  defp filter_by_scenario(sessions, nil), do: sessions

  defp filter_by_scenario(sessions, scenario) do
    Enum.filter(sessions, fn session -> session.scenario == scenario end)
  end

  defp filter_by_status(sessions, nil), do: sessions

  defp filter_by_status(sessions, status) do
    status_atom = String.to_existing_atom(status)
    Enum.filter(sessions, fn session -> session.status == status_atom end)
  end

  defp filter_by_date_range(sessions, nil, nil), do: sessions

  defp filter_by_date_range(sessions, date_from, date_to) do
    from_datetime = if date_from, do: DateTime.from_iso8601(date_from), else: nil
    to_datetime = if date_to, do: DateTime.from_iso8601(date_to), else: nil

    Enum.filter(sessions, fn session ->
      session_date = session.created_at

      from_ok =
        case from_datetime do
          {:ok, from_dt, _} -> DateTime.compare(session_date, from_dt) != :lt
          _ -> true
        end

      to_ok =
        case to_datetime do
          {:ok, to_dt, _} -> DateTime.compare(session_date, to_dt) != :gt
          _ -> true
        end

      from_ok and to_ok
    end)
  end

  defp session_summary(session) do
    %{
      id: session.id,
      scenario: session.scenario,
      participants: session.participants,
      status: session.status,
      created_at: session.created_at,
      total_turns: length(session.conversation_tree.nodes),
      total_branches: count_unique_branches(session.conversation_tree),
      ended_at: Map.get(session, :ended_at)
    }
  end

  defp count_unique_branches(tree) do
    tree.nodes
    |> Enum.map(&Map.get(&1, :branch_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> length()
  end

  defp analyze_conversation_session(session) do
    nodes = session.conversation_tree.nodes

    %{
      session_id: session.id,
      scenario: session.scenario,
      total_duration: calculate_session_duration(session),
      conversation_flow: analyze_conversation_flow(nodes),
      sentiment_progression: analyze_sentiment_progression(nodes),
      branch_analysis: analyze_branching_patterns(nodes),
      effectiveness_scores: calculate_effectiveness_scores(nodes, session.scenario),
      recommendations: generate_session_recommendations(nodes, session.scenario),
      completion_status: determine_completion_status(session)
    }
  end

  defp calculate_session_duration(session) do
    case {session.created_at, Map.get(session, :ended_at)} do
      {start_time, nil} -> DateTime.diff(DateTime.utc_now(), start_time, :second)
      {start_time, end_time} -> DateTime.diff(end_time, start_time, :second)
    end
  end

  defp analyze_conversation_flow(nodes) do
    speakers = nodes |> Enum.map(& &1.speaker) |> Enum.frequencies()

    %{
      total_turns: length(nodes),
      speaker_distribution: speakers,
      avg_response_time: calculate_avg_response_time(nodes),
      conversation_balance: calculate_conversation_balance(speakers)
    }
  end

  defp analyze_sentiment_progression(nodes) do
    sentiments =
      Enum.map(nodes, fn node ->
        %{
          timestamp: node.timestamp,
          sentiment: analyze_message_sentiment(node.message)
        }
      end)

    %{
      progression: sentiments,
      overall_trend: calculate_sentiment_trend(sentiments),
      positive_moments: count_sentiment_type(sentiments, :positive),
      negative_moments: count_sentiment_type(sentiments, :negative)
    }
  end

  defp analyze_branching_patterns(nodes) do
    branches = nodes |> Enum.group_by(&Map.get(&1, :branch_id)) |> Map.delete(nil)

    %{
      total_branches: map_size(branches),
      branch_utilization: calculate_branch_utilization(branches),
      most_explored_paths: find_most_explored_paths(branches)
    }
  end

  defp calculate_effectiveness_scores(nodes, scenario) do
    base_score = %{
      communication_clarity: 7.5,
      goal_achievement: 6.0,
      engagement_level: 7.0,
      adaptability: 8.0
    }

    # Adjust scores based on scenario-specific factors
    case scenario do
      "job_interview" ->
        Map.merge(base_score, %{
          confidence_display: 7.5,
          competence_demonstration: 7.0,
          cultural_fit: 8.0
        })

      "sales_call" ->
        Map.merge(base_score, %{
          value_articulation: 7.0,
          objection_handling: 6.5,
          closing_ability: 6.0
        })

      _ ->
        base_score
    end
  end

  defp generate_session_recommendations(nodes, scenario) do
    base_recommendations = [
      "Practice active listening techniques",
      "Work on maintaining consistent energy throughout the conversation"
    ]

    scenario_recommendations =
      case scenario do
        "job_interview" ->
          [
            "Prepare more specific examples using the STAR method",
            "Practice confident body language",
            "Research common follow-up questions"
          ]

        "sales_call" ->
          [
            "Focus on asking better discovery questions",
            "Practice handling price objections",
            "Develop stronger closing techniques"
          ]

        _ ->
          []
      end

    base_recommendations ++ scenario_recommendations
  end

  defp determine_completion_status(session) do
    case session.status do
      :ended ->
        :completed

      :active ->
        if length(session.conversation_tree.nodes) > 10 do
          :substantial_progress
        else
          :early_stage
        end
    end
  end

  # Helper functions
  defp analyze_message_sentiment(message) when is_binary(message) do
    positive_words =
      ~w[good great excellent amazing wonderful fantastic happy joy love appreciate thank]

    negative_words =
      ~w[bad terrible awful horrible sad angry hate disappointing frustrated annoyed]

    words = message |> String.downcase() |> String.split()
    positive_count = Enum.count(words, &(&1 in positive_words))
    negative_count = Enum.count(words, &(&1 in negative_words))

    cond do
      positive_count > negative_count -> :positive
      negative_count > positive_count -> :negative
      true -> :neutral
    end
  end

  defp analyze_message_sentiment(_), do: :neutral

  defp calculate_avg_response_time(nodes) when length(nodes) < 2, do: 0

  defp calculate_avg_response_time(nodes) do
    nodes
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [prev, curr] -> DateTime.diff(curr.timestamp, prev.timestamp, :second) end)
    |> Enum.sum()
    |> div(max(length(nodes) - 1, 1))
  end

  defp calculate_conversation_balance(speaker_frequencies) do
    if map_size(speaker_frequencies) < 2 do
      :unbalanced
    else
      values = Map.values(speaker_frequencies)
      max_val = Enum.max(values)
      min_val = Enum.min(values)

      if max_val / min_val <= 2, do: :balanced, else: :unbalanced
    end
  end

  defp calculate_sentiment_trend(sentiments) when length(sentiments) < 3, do: :insufficient_data

  defp calculate_sentiment_trend(sentiments) do
    # Simple trend calculation based on first and last third of conversation
    total = length(sentiments)
    first_third = Enum.take(sentiments, div(total, 3))
    last_third = Enum.take(sentiments, -div(total, 3))

    first_positive = count_sentiment_type(first_third, :positive)
    last_positive = count_sentiment_type(last_third, :positive)

    cond do
      last_positive > first_positive -> :improving
      last_positive < first_positive -> :declining
      true -> :stable
    end
  end

  defp count_sentiment_type(sentiments, type) do
    Enum.count(sentiments, fn %{sentiment: sentiment} -> sentiment == type end)
  end

  defp calculate_branch_utilization(branches) when map_size(branches) == 0, do: 0.0

  defp calculate_branch_utilization(branches) do
    branch_sizes = branches |> Map.values() |> Enum.map(&length/1)
    avg_size = Enum.sum(branch_sizes) / length(branch_sizes)
    # Normalize to 0-1 scale
    min(avg_size / 5.0, 1.0)
  end

  defp find_most_explored_paths(branches) do
    branches
    |> Enum.map(fn {branch_id, nodes} -> {branch_id, length(nodes)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(3)
  end

  defp generate_session_id, do: :crypto.strong_rand_bytes(16) |> Base.encode64()
  defp generate_node_id, do: :crypto.strong_rand_bytes(8) |> Base.encode64()
  defp generate_branch_id, do: :crypto.strong_rand_bytes(8) |> Base.encode64()
end
