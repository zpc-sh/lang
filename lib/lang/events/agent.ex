defmodule Lang.Events.Agent do
  @moduledoc """
  Agent event tracking for the LANG cognitive operating system.

  This module handles all agent-related events including lifecycle, security,
  behavioral monitoring, and coordination activities.
  """

  alias Lang.Events.EventStore

  @doc """
  Track agent spawn event with initial capabilities and constraints.
  """
  def track_spawn(agent_id, capabilities, constraints, context \\ %{}) do
    event_data = %{
      agent_id: agent_id,
      capabilities: capabilities,
      constraints: constraints,
      spawned_at: DateTime.utc_now()
    }

    EventStore.track_event(%{
      event_type: :agent_spawned,
      entity_type: :agent,
      entity_id: agent_id,
      data: event_data,
      context: context,
      severity: :info,
      tags: ["agent", "lifecycle", "spawn"]
    })
  end

  @doc """
  Track agent termination event with reason and final state.
  """
  def track_termination(agent_id, reason, final_state, context \\ %{}) do
    event_data = %{
      agent_id: agent_id,
      termination_reason: reason,
      final_state: final_state,
      terminated_at: DateTime.utc_now()
    }

    severity =
      case reason do
        "normal" -> :info
        "timeout" -> :warning
        "error" -> :error
        "quarantine" -> :critical
        _ -> :warning
      end

    EventStore.track_event(%{
      event_type: :agent_terminated,
      entity_type: :agent,
      entity_id: agent_id,
      data: event_data,
      context: context,
      severity: severity,
      tags: ["agent", "lifecycle", "termination"]
    })
  end

  @doc """
  Track agent delegation event when tasks are assigned to agents.
  """
  def track_delegation(delegator_id, agent_id, task, context \\ %{}) do
    event_data = %{
      delegator_id: delegator_id,
      agent_id: agent_id,
      task_type: Map.get(task, :type),
      task_complexity: Map.get(task, :complexity, :unknown),
      delegated_at: DateTime.utc_now()
    }

    EventStore.track_event(%{
      event_type: :agent_delegated,
      entity_type: :agent,
      entity_id: agent_id,
      data: event_data,
      context: context,
      severity: :info,
      tags: ["agent", "coordination", "delegation"]
    })
  end

  @doc """
  Track multi-agent coordination events for ACG protocol monitoring.
  """
  def track_coordination(coordinator_id, agent_ids, task, coordination_graph, context \\ %{}) do
    event_data = %{
      coordinator_id: coordinator_id,
      agent_ids: agent_ids,
      agent_count: length(agent_ids),
      task_type: Map.get(task, :type),
      coordination_strategy: Map.get(coordination_graph, :strategy),
      coordinated_at: DateTime.utc_now()
    }

    EventStore.track_event(%{
      event_type: :agent_coordination,
      entity_type: :coordination_graph,
      entity_id: coordinator_id,
      data: event_data,
      context: context,
      severity: :info,
      tags: ["agent", "coordination", "acg_protocol"]
    })
  end

  @doc """
  Track security scanning events for behavioral monitoring.
  """
  def track_security_scan(scanner_id, target_agent_id, scan_results, context \\ %{}) do
    event_data = %{
      scanner_id: scanner_id,
      target_agent_id: target_agent_id,
      scan_results: scan_results,
      anomaly_score: Map.get(scan_results, :anomaly_score, 0.0),
      trust_score: Map.get(scan_results, :trust_score, 1.0),
      scanned_at: DateTime.utc_now()
    }

    severity =
      case Map.get(scan_results, :threat_level) do
        :none -> :info
        :low -> :info
        :medium -> :warning
        :high -> :error
        :critical -> :critical
        _ -> :info
      end

    EventStore.track_event(%{
      event_type: :agent_security_scan,
      entity_type: :agent,
      entity_id: target_agent_id,
      data: event_data,
      context: context,
      severity: severity,
      tags: ["agent", "security", "behavioral_monitoring"]
    })
  end

  @doc """
  Track rogue agent detection events with quarantine actions.
  """
  def track_rogue_detection(
        detector_id,
        rogue_agent_id,
        detection_data,
        action_taken,
        context \\ %{}
      ) do
    event_data = %{
      detector_id: detector_id,
      rogue_agent_id: rogue_agent_id,
      detection_data: detection_data,
      action_taken: action_taken,
      anomaly_score: Map.get(detection_data, :anomaly_score),
      behavioral_deviations: Map.get(detection_data, :deviations),
      detected_at: DateTime.utc_now()
    }

    EventStore.track_event(%{
      event_type: :rogue_agent_detected,
      entity_type: :agent,
      entity_id: rogue_agent_id,
      data: event_data,
      context: context,
      severity: :critical,
      tags: ["agent", "security", "rogue_detection", "critical"]
    })
  end

  @doc """
  Track agent quarantine events with reason and security measures.
  """
  def track_quarantine(
        quarantining_agent_id,
        quarantined_agent_id,
        reason,
        security_measures,
        context \\ %{}
      ) do
    event_data = %{
      quarantining_agent_id: quarantining_agent_id,
      quarantined_agent_id: quarantined_agent_id,
      quarantine_reason: reason,
      security_measures: security_measures,
      quarantined_at: DateTime.utc_now()
    }

    EventStore.track_event(%{
      event_type: :agent_quarantined,
      entity_type: :agent,
      entity_id: quarantined_agent_id,
      data: event_data,
      context: context,
      severity: :critical,
      tags: ["agent", "security", "quarantine", "isolation"]
    })
  end

  @doc """
  Track behavioral baseline establishment for new agents.
  """
  def track_baseline_establishment(agent_id, baseline_data, context \\ %{}) do
    event_data = %{
      agent_id: agent_id,
      baseline_data: baseline_data,
      baseline_version: "1.0",
      established_at: DateTime.utc_now()
    }

    EventStore.track_event(%{
      event_type: :behavioral_baseline_established,
      entity_type: :agent,
      entity_id: agent_id,
      data: event_data,
      context: context,
      severity: :info,
      tags: ["agent", "behavioral", "baseline"]
    })
  end

  @doc """
  Track trust score updates with reasoning and previous values.
  """
  def track_trust_update(agent_id, old_score, new_score, reason, context \\ %{}) do
    event_data = %{
      agent_id: agent_id,
      old_trust_score: old_score,
      new_trust_score: new_score,
      score_change: new_score - old_score,
      reason: reason,
      updated_at: DateTime.utc_now()
    }

    severity =
      cond do
        new_score < 0.3 -> :error
        new_score < 0.5 -> :warning
        true -> :info
      end

    EventStore.track_event(%{
      event_type: :agent_trust_updated,
      entity_type: :agent,
      entity_id: agent_id,
      data: event_data,
      context: context,
      severity: severity,
      tags: ["agent", "trust", "scoring"]
    })
  end

  @doc """
  Track resource usage events for monitoring and throttling.
  """
  def track_resource_usage(agent_id, resource_type, amount, limits, context \\ %{}) do
    usage_percentage =
      case Map.get(limits, resource_type) do
        nil -> 0.0
        limit when limit > 0 -> amount / limit * 100
        _ -> 0.0
      end

    event_data = %{
      agent_id: agent_id,
      resource_type: resource_type,
      amount_used: amount,
      usage_percentage: usage_percentage,
      limits: limits,
      recorded_at: DateTime.utc_now()
    }

    severity =
      cond do
        usage_percentage > 90 -> :error
        usage_percentage > 75 -> :warning
        true -> :info
      end

    EventStore.track_event(%{
      event_type: :agent_resource_usage,
      entity_type: :agent,
      entity_id: agent_id,
      data: event_data,
      context: context,
      severity: severity,
      tags: ["agent", "resources", "monitoring"]
    })
  end

  @doc """
  Track cognitive load monitoring for QCP integration.
  """
  def track_cognitive_load(agent_id, qcp_metrics, overall_load, context \\ %{}) do
    event_data = %{
      agent_id: agent_id,
      qcp_metrics: qcp_metrics,
      overall_cognitive_load: overall_load,
      load_level: cognitive_load_level(overall_load),
      measured_at: DateTime.utc_now()
    }

    severity =
      case cognitive_load_level(overall_load) do
        :critical -> :error
        :high -> :warning
        _ -> :info
      end

    EventStore.track_event(%{
      event_type: :agent_cognitive_load,
      entity_type: :agent,
      entity_id: agent_id,
      data: event_data,
      context: context,
      severity: severity,
      tags: ["agent", "cognitive", "qcp", "monitoring"]
    })
  end

  @doc """
  Track capability updates (grants/revokes) for security monitoring.
  """
  def track_capability_change(agent_id, action, capability, authorizer_id, context \\ %{}) do
    event_data = %{
      agent_id: agent_id,
      # :grant or :revoke
      action: action,
      capability: capability,
      authorizer_id: authorizer_id,
      changed_at: DateTime.utc_now()
    }

    severity =
      case {action, capability} do
        {:grant, cap} when cap in [:system_wide, :architecture_changes] -> :warning
        {:revoke, _} -> :info
        _ -> :info
      end

    EventStore.track_event(%{
      event_type: :agent_capability_changed,
      entity_type: :agent,
      entity_id: agent_id,
      data: event_data,
      context: context,
      severity: severity,
      tags: ["agent", "capabilities", "security"]
    })
  end

  @doc """
  Track inter-agent communication events for coordination monitoring.
  """
  def track_communication(from_agent_id, to_agent_id, message_type, message_size, context \\ %{}) do
    event_data = %{
      from_agent_id: from_agent_id,
      to_agent_id: to_agent_id,
      message_type: message_type,
      message_size_bytes: message_size,
      sent_at: DateTime.utc_now()
    }

    EventStore.track_event(%{
      event_type: :agent_communication,
      entity_type: :agent,
      entity_id: from_agent_id,
      data: event_data,
      context: context,
      severity: :info,
      tags: ["agent", "communication", "coordination"]
    })
  end

  @doc """
  Track pattern learning events for knowledge management.
  """
  def track_pattern_learned(agent_id, pattern_type, pattern_data, confidence, context \\ %{}) do
    event_data = %{
      agent_id: agent_id,
      pattern_type: pattern_type,
      pattern_data: pattern_data,
      confidence_score: confidence,
      learned_at: DateTime.utc_now()
    }

    EventStore.track_event(%{
      event_type: :agent_pattern_learned,
      entity_type: :agent,
      entity_id: agent_id,
      data: event_data,
      context: context,
      severity: :info,
      tags: ["agent", "learning", "patterns"]
    })
  end

  @doc """
  Get agent event history for forensic analysis and behavioral tracking.
  """
  def get_agent_history(agent_id, options \\ %{}) do
    filters = %{
      entity_type: :agent,
      entity_id: agent_id
    }

    filters =
      case Map.get(options, :event_types) do
        nil -> filters
        types -> Map.put(filters, :event_types, types)
      end

    filters =
      case Map.get(options, :severity) do
        nil -> filters
        severity -> Map.put(filters, :severity, severity)
      end

    time_range = Map.get(options, :time_range)
    limit = Map.get(options, :limit, 100)

    EventStore.get_events(filters, time_range: time_range, limit: limit)
  end

  @doc """
  Get security events for all agents for threat analysis.
  """
  def get_security_events(options \\ %{}) do
    filters = %{
      entity_type: :agent,
      tags: ["security"]
    }

    severity_filter = Map.get(options, :severity, [:warning, :error, :critical])
    filters = Map.put(filters, :severity, severity_filter)

    time_range = Map.get(options, :time_range)
    limit = Map.get(options, :limit, 500)

    EventStore.get_events(filters, time_range: time_range, limit: limit)
  end

  @doc """
  Get coordination events for ACG protocol analysis.
  """
  def get_coordination_events(options \\ %{}) do
    filters = %{
      entity_type: :coordination_graph,
      tags: ["coordination"]
    }

    time_range = Map.get(options, :time_range)
    limit = Map.get(options, :limit, 200)

    EventStore.get_events(filters, time_range: time_range, limit: limit)
  end

  # Private helper functions

  defp cognitive_load_level(load) when load < 0.3, do: :low
  defp cognitive_load_level(load) when load < 0.6, do: :medium
  defp cognitive_load_level(load) when load < 0.8, do: :high
  defp cognitive_load_level(_), do: :critical
end
