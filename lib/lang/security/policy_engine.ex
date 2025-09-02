defmodule Lang.Security.PolicyEngine do
  @moduledoc """
  Dynamic security policy engine with adaptive rule management.
  
  Features:
  - Dynamic security policy creation and updates
  - Conditional rule activation based on threat levels
  - Policy versioning and rollback capabilities
  - Integration with threat intelligence for adaptive responses
  - Real-time policy evaluation and enforcement
  """
  
  use GenServer
  require Logger
  
  alias Lang.Security.ThreatIntelligence
  alias Lang.Monitoring.SecurityMonitor
  alias Lang.Redis
  
  @policy_store_key "security_policies"
  @active_rules_key "active_security_rules"
  @policy_history_key "policy_history"
  
  @rule_types [
    :rate_limiting,
    :access_control,
    :input_validation,
    :response_filtering,
    :session_management,
    :threat_response
  ]
  
  @enforcement_modes [:monitor, :warn, :block, :quarantine]
  
  @type policy :: %{
    id: String.t(),
    name: String.t(),
    description: String.t(),
    rules: [security_rule()],
    conditions: [condition()],
    enforcement_mode: atom(),
    priority: integer(),
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    version: integer(),
    active: boolean()
  }
  
  @type security_rule :: %{
    id: String.t(),
    type: atom(),
    name: String.t(),
    conditions: [condition()],
    actions: [action()],
    parameters: map(),
    enabled: boolean()
  }
  
  @type condition :: %{
    field: String.t(),
    operator: String.t(),
    value: term(),
    negate: boolean()
  }
  
  @type action :: %{
    type: atom(),
    parameters: map()
  }
  
  defstruct [
    :policies,
    :active_rules,
    :policy_history,
    :threat_level,
    :adaptive_mode,
    :stats
  ]
  
  ## Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Evaluates a security context against active policies.
  """
  @spec evaluate_policies(map()) :: {:ok, [action()]} | {:error, term()}
  def evaluate_policies(context) do
    GenServer.call(__MODULE__, {:evaluate_policies, context})
  end
  
  @doc """
  Creates a new security policy.
  """
  @spec create_policy(map()) :: {:ok, String.t()} | {:error, term()}
  def create_policy(policy_spec) do
    GenServer.call(__MODULE__, {:create_policy, policy_spec})
  end
  
  @doc """
  Updates an existing security policy.
  """
  @spec update_policy(String.t(), map()) :: :ok | {:error, term()}
  def update_policy(policy_id, updates) do
    GenServer.call(__MODULE__, {:update_policy, policy_id, updates})
  end
  
  @doc """
  Activates or deactivates a policy.
  """
  @spec toggle_policy(String.t(), boolean()) :: :ok | {:error, term()}
  def toggle_policy(policy_id, active) do
    GenServer.call(__MODULE__, {:toggle_policy, policy_id, active})
  end
  
  @doc """
  Gets all active policies.
  """
  @spec get_active_policies() :: [policy()]
  def get_active_policies do
    GenServer.call(__MODULE__, :get_active_policies)
  end
  
  @doc """
  Creates adaptive policies based on current threat intelligence.
  """
  @spec create_adaptive_policies() :: {:ok, [String.t()]} | {:error, term()}
  def create_adaptive_policies do
    GenServer.call(__MODULE__, :create_adaptive_policies)
  end
  
  @doc """
  Gets policy engine statistics and status.
  """
  @spec get_policy_stats() :: map()
  def get_policy_stats do
    GenServer.call(__MODULE__, :get_policy_stats)
  end
  
  ## GenServer Implementation
  
  def init(_opts) do
    # Load existing policies
    state = %__MODULE__{
      policies: load_policies(),
      active_rules: load_active_rules(),
      policy_history: load_policy_history(),
      threat_level: :normal,
      adaptive_mode: true,
      stats: %{
        evaluations: 0,
        policy_matches: 0,
        actions_triggered: 0,
        adaptive_policies_created: 0
      }
    }
    
    # Schedule periodic policy updates based on threat intelligence
    schedule_adaptive_update()
    
    Logger.info("Security Policy Engine initialized")
    {:ok, state}
  end
  
  def handle_call({:evaluate_policies, context}, _from, state) do
    # Get applicable policies based on context
    applicable_policies = get_applicable_policies(state.policies, context)
    
    # Evaluate each policy
    evaluation_results = Enum.map(applicable_policies, fn policy ->
      evaluate_single_policy(policy, context)
    end)
    
    # Aggregate actions from all matching policies
    actions = aggregate_policy_actions(evaluation_results)
    
    # Update statistics
    updated_stats = %{
      state.stats |
      evaluations: state.stats.evaluations + 1,
      policy_matches: state.stats.policy_matches + length(applicable_policies),
      actions_triggered: state.stats.actions_triggered + length(actions)
    }
    
    new_state = %{state | stats: updated_stats}
    
    # Log policy evaluation
    log_policy_evaluation(context, applicable_policies, actions)
    
    {:reply, {:ok, actions}, new_state}
  end
  
  def handle_call({:create_policy, policy_spec}, _from, state) do
    case validate_policy_spec(policy_spec) do
      :ok ->
        policy = create_policy_from_spec(policy_spec)
        new_policies = Map.put(state.policies, policy.id, policy)
        
        # Update active rules if policy is active
        new_active_rules = if policy.active do
          update_active_rules(state.active_rules, policy)
        else
          state.active_rules
        end
        
        # Add to policy history
        history_entry = create_history_entry(:created, policy)
        new_history = [history_entry | state.policy_history] |> Enum.take(100)
        
        new_state = %{state |
          policies: new_policies,
          active_rules: new_active_rules,
          policy_history: new_history
        }
        
        # Persist changes
        persist_policies(new_policies)
        persist_active_rules(new_active_rules)
        persist_policy_history(new_history)
        
        Logger.info("Created security policy", policy_id: policy.id, name: policy.name)
        {:reply, {:ok, policy.id}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:update_policy, policy_id, updates}, _from, state) do
    case Map.get(state.policies, policy_id) do
      nil ->
        {:reply, {:error, :policy_not_found}, state}
      
      existing_policy ->
        updated_policy = update_policy_struct(existing_policy, updates)
        
        case validate_policy_struct(updated_policy) do
          :ok ->
            new_policies = Map.put(state.policies, policy_id, updated_policy)
            
            # Update active rules
            new_active_rules = if updated_policy.active do
              update_active_rules(state.active_rules, updated_policy)
            else
              remove_policy_from_active_rules(state.active_rules, policy_id)
            end
            
            # Add to history
            history_entry = create_history_entry(:updated, updated_policy)
            new_history = [history_entry | state.policy_history] |> Enum.take(100)
            
            new_state = %{state |
              policies: new_policies,
              active_rules: new_active_rules,
              policy_history: new_history
            }
            
            # Persist changes
            persist_policies(new_policies)
            persist_active_rules(new_active_rules)
            persist_policy_history(new_history)
            
            Logger.info("Updated security policy", policy_id: policy_id)
            {:reply, :ok, new_state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  def handle_call({:toggle_policy, policy_id, active}, _from, state) do
    case Map.get(state.policies, policy_id) do
      nil ->
        {:reply, {:error, :policy_not_found}, state}
      
      policy ->
        updated_policy = %{policy | active: active, updated_at: DateTime.utc_now()}
        new_policies = Map.put(state.policies, policy_id, updated_policy)
        
        # Update active rules
        new_active_rules = if active do
          update_active_rules(state.active_rules, updated_policy)
        else
          remove_policy_from_active_rules(state.active_rules, policy_id)
        end
        
        # Add to history
        action = if active, do: :activated, else: :deactivated
        history_entry = create_history_entry(action, updated_policy)
        new_history = [history_entry | state.policy_history] |> Enum.take(100)
        
        new_state = %{state |
          policies: new_policies,
          active_rules: new_active_rules,
          policy_history: new_history
        }
        
        # Persist changes
        persist_policies(new_policies)
        persist_active_rules(new_active_rules)
        
        Logger.info("Toggled security policy", 
          policy_id: policy_id, 
          active: active
        )
        {:reply, :ok, new_state}
    end
  end
  
  def handle_call(:get_active_policies, _from, state) do
    active_policies = state.policies
      |> Enum.filter(fn {_id, policy} -> policy.active end)
      |> Enum.map(fn {_id, policy} -> policy end)
      |> Enum.sort_by(& &1.priority, :desc)
    
    {:reply, active_policies, state}
  end
  
  def handle_call(:create_adaptive_policies, _from, state) do
    Logger.info("Creating adaptive security policies based on threat intelligence")
    
    # Get threat intelligence recommendations
    case ThreatIntelligence.get_adaptive_recommendations() do
      recommendations when is_list(recommendations) ->
        new_policies = Enum.map(recommendations, &create_adaptive_policy/1)
        
        # Add new policies to state
        policy_map = Enum.reduce(new_policies, state.policies, fn policy, acc ->
          Map.put(acc, policy.id, policy)
        end)
        
        # Update active rules for new policies
        new_active_rules = Enum.reduce(new_policies, state.active_rules, fn policy, acc ->
          if policy.active, do: update_active_rules(acc, policy), else: acc
        end)
        
        # Update stats
        updated_stats = %{
          state.stats |
          adaptive_policies_created: state.stats.adaptive_policies_created + length(new_policies)
        }
        
        new_state = %{state |
          policies: policy_map,
          active_rules: new_active_rules,
          stats: updated_stats
        }
        
        # Persist changes
        persist_policies(policy_map)
        persist_active_rules(new_active_rules)
        
        policy_ids = Enum.map(new_policies, & &1.id)
        {:reply, {:ok, policy_ids}, new_state}
      
      _ ->
        {:reply, {:error, :no_recommendations}, state}
    end
  end
  
  def handle_call(:get_policy_stats, _from, state) do
    stats = %{
      total_policies: map_size(state.policies),
      active_policies: Enum.count(state.policies, fn {_id, policy} -> policy.active end),
      total_rules: count_total_rules(state.policies),
      active_rules: length(state.active_rules),
      threat_level: state.threat_level,
      adaptive_mode: state.adaptive_mode,
      evaluation_stats: state.stats,
      recent_history: Enum.take(state.policy_history, 10)
    }
    
    {:reply, stats, state}
  end
  
  def handle_info(:adaptive_policy_update, state) do
    # Schedule next update
    schedule_adaptive_update()
    
    # Check current threat level and adapt policies accordingly
    new_state = adapt_policies_to_threat_level(state)
    
    {:noreply, new_state}
  end
  
  ## Private Functions - Policy Evaluation
  
  defp get_applicable_policies(policies, context) do
    policies
    |> Enum.filter(fn {_id, policy} -> 
      policy.active and evaluate_policy_conditions(policy.conditions, context)
    end)
    |> Enum.map(fn {_id, policy} -> policy end)
    |> Enum.sort_by(& &1.priority, :desc)
  end
  
  defp evaluate_single_policy(policy, context) do
    matching_rules = Enum.filter(policy.rules, fn rule ->
      rule.enabled and evaluate_rule_conditions(rule.conditions, context)
    end)
    
    actions = Enum.flat_map(matching_rules, & &1.actions)
    
    %{
      policy: policy,
      matching_rules: matching_rules,
      actions: actions,
      enforcement_mode: policy.enforcement_mode
    }
  end
  
  defp evaluate_policy_conditions(conditions, context) do
    Enum.all?(conditions, &evaluate_condition(&1, context))
  end
  
  defp evaluate_rule_conditions(conditions, context) do
    Enum.all?(conditions, &evaluate_condition(&1, context))
  end
  
  defp evaluate_condition(condition, context) do
    value = get_context_value(context, condition.field)
    result = compare_values(value, condition.operator, condition.value)
    
    if condition.negate, do: not result, else: result
  end
  
  defp get_context_value(context, field) do
    case String.split(field, ".") do
      [single_field] -> Map.get(context, single_field)
      path -> get_in(context, path)
    end
  end
  
  defp compare_values(actual, "equals", expected), do: actual == expected
  defp compare_values(actual, "not_equals", expected), do: actual != expected
  defp compare_values(actual, "greater_than", expected) when is_number(actual) and is_number(expected), do: actual > expected
  defp compare_values(actual, "less_than", expected) when is_number(actual) and is_number(expected), do: actual < expected
  defp compare_values(actual, "contains", expected) when is_binary(actual) and is_binary(expected), do: String.contains?(actual, expected)
  defp compare_values(actual, "matches", expected) when is_binary(actual), do: Regex.match?(~r/#{expected}/, actual)
  defp compare_values(actual, "in", expected) when is_list(expected), do: actual in expected
  defp compare_values(_actual, _operator, _expected), do: false
  
  defp aggregate_policy_actions(evaluation_results) do
    evaluation_results
    |> Enum.flat_map(& &1.actions)
    |> Enum.uniq_by(& {&1.type, &1.parameters})
    |> prioritize_actions()
  end
  
  defp prioritize_actions(actions) do
    # Sort actions by priority (block > warn > monitor)
    priority_order = %{
      quarantine: 4,
      block: 3,
      warn: 2,
      monitor: 1
    }
    
    Enum.sort_by(actions, fn action ->
      Map.get(priority_order, action.type, 0)
    end, :desc)
  end
  
  ## Private Functions - Policy Management
  
  defp validate_policy_spec(spec) do
    required_fields = [:name, :description, :rules]
    
    case Enum.find(required_fields, &(not Map.has_key?(spec, &1))) do
      nil ->
        if validate_rules(spec[:rules]) do
          :ok
        else
          {:error, :invalid_rules}
        end
      
      missing_field ->
        {:error, {:missing_field, missing_field}}
    end
  end
  
  defp validate_rules(rules) when is_list(rules) do
    Enum.all?(rules, &validate_single_rule/1)
  end
  defp validate_rules(_), do: false
  
  defp validate_single_rule(rule) do
    required_fields = [:name, :type, :actions]
    Enum.all?(required_fields, &Map.has_key?(rule, &1)) and
    rule[:type] in @rule_types
  end
  
  defp validate_policy_struct(policy) do
    if policy.name and policy.description and is_list(policy.rules) do
      :ok
    else
      {:error, :invalid_policy_structure}
    end
  end
  
  defp create_policy_from_spec(spec) do
    policy_id = generate_policy_id()
    
    %{
      id: policy_id,
      name: spec[:name],
      description: spec[:description],
      rules: normalize_rules(spec[:rules]),
      conditions: spec[:conditions] || [],
      enforcement_mode: spec[:enforcement_mode] || :block,
      priority: spec[:priority] || 100,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      version: 1,
      active: spec[:active] != false
    }
  end
  
  defp normalize_rules(rules) do
    Enum.map(rules, fn rule ->
      %{
        id: generate_rule_id(),
        type: rule[:type],
        name: rule[:name],
        conditions: rule[:conditions] || [],
        actions: normalize_actions(rule[:actions]),
        parameters: rule[:parameters] || %{},
        enabled: rule[:enabled] != false
      }
    end)
  end
  
  defp normalize_actions(actions) when is_list(actions) do
    Enum.map(actions, fn action ->
      if is_atom(action) do
        %{type: action, parameters: %{}}
      else
        action
      end
    end)
  end
  
  defp update_policy_struct(policy, updates) do
    %{policy |
      name: Map.get(updates, :name, policy.name),
      description: Map.get(updates, :description, policy.description),
      rules: Map.get(updates, :rules, policy.rules) |> normalize_rules(),
      conditions: Map.get(updates, :conditions, policy.conditions),
      enforcement_mode: Map.get(updates, :enforcement_mode, policy.enforcement_mode),
      priority: Map.get(updates, :priority, policy.priority),
      updated_at: DateTime.utc_now(),
      version: policy.version + 1
    }
  end
  
  defp update_active_rules(active_rules, policy) do
    # Remove existing rules for this policy
    filtered_rules = Enum.reject(active_rules, fn rule ->
      String.starts_with?(rule.id, policy.id)
    end)
    
    # Add new active rules from policy
    new_rules = Enum.filter(policy.rules, & &1.enabled)
    filtered_rules ++ new_rules
  end
  
  defp remove_policy_from_active_rules(active_rules, policy_id) do
    Enum.reject(active_rules, fn rule ->
      String.starts_with?(rule.id, policy_id)
    end)
  end
  
  ## Private Functions - Adaptive Policies
  
  defp create_adaptive_policy(recommendation) do
    policy_spec = case recommendation.type do
      :rate_limiting ->
        create_rate_limiting_policy(recommendation)
      
      :validation_rules ->
        create_validation_policy(recommendation)
      
      :access_control ->
        create_access_control_policy(recommendation)
      
      _ ->
        create_generic_adaptive_policy(recommendation)
    end
    
    create_policy_from_spec(policy_spec)
  end
  
  defp create_rate_limiting_policy(recommendation) do
    %{
      name: "Adaptive Rate Limiting",
      description: "Auto-generated rate limiting policy based on threat intelligence",
      enforcement_mode: :warn,
      priority: 90,
      rules: [
        %{
          name: "Enhanced Rate Limits",
          type: :rate_limiting,
          conditions: [
            %{field: "client_id", operator: "in", value: recommendation.indicators || []}
          ],
          actions: [
            %{type: :rate_limit, parameters: %{limit: 10, window: 60}}
          ]
        }
      ]
    }
  end
  
  defp create_validation_policy(recommendation) do
    %{
      name: "Adaptive Input Validation",
      description: "Enhanced validation rules based on attack patterns",
      enforcement_mode: :block,
      priority: 95,
      rules: [
        %{
          name: "Pattern-Based Validation",
          type: :input_validation,
          conditions: [
            %{field: "method", operator: "matches", value: "lang\\..*"}
          ],
          actions: [
            %{type: :enhanced_validation, parameters: %{patterns: recommendation.patterns || []}}
          ]
        }
      ]
    }
  end
  
  defp create_access_control_policy(recommendation) do
    %{
      name: "Adaptive Access Control",
      description: "Tightened access controls based on threat activity",
      enforcement_mode: :block,
      priority: 85,
      rules: [
        %{
          name: "Threat-Based Access Control",
          type: :access_control,
          conditions: [
            %{field: "threat_score", operator: "greater_than", value: 50}
          ],
          actions: [
            %{type: :require_elevated_auth, parameters: %{}}
          ]
        }
      ]
    }
  end
  
  defp create_generic_adaptive_policy(recommendation) do
    %{
      name: "Generic Adaptive Policy",
      description: "Adaptive policy: #{recommendation.description}",
      enforcement_mode: :warn,
      priority: 80,
      rules: [
        %{
          name: "Generic Adaptive Rule",
          type: :threat_response,
          conditions: [],
          actions: [
            %{type: :log_event, parameters: %{reason: "adaptive_policy_match"}}
          ]
        }
      ]
    }
  end
  
  defp adapt_policies_to_threat_level(state) do
    # Get current threat level from threat intelligence
    current_threat = get_current_threat_level()
    
    if current_threat != state.threat_level do
      Logger.info("Adapting policies to threat level change", 
        from: state.threat_level, 
        to: current_threat
      )
      
      # Adjust enforcement modes based on threat level
      adapted_policies = adapt_enforcement_modes(state.policies, current_threat)
      
      # Update active rules
      new_active_rules = rebuild_active_rules(adapted_policies)
      
      # Persist changes
      persist_policies(adapted_policies)
      persist_active_rules(new_active_rules)
      
      %{state |
        policies: adapted_policies,
        active_rules: new_active_rules,
        threat_level: current_threat
      }
    else
      state
    end
  end
  
  defp get_current_threat_level do
    # Get threat level from threat intelligence system
    case ThreatIntelligence.get_threat_summary() do
      %{stats: %{threats_detected: threats}} when threats > 10 -> :high
      %{stats: %{threats_detected: threats}} when threats > 5 -> :medium
      %{stats: %{threats_detected: threats}} when threats > 0 -> :low
      _ -> :normal
    end
  rescue
    _ -> :normal
  end
  
  defp adapt_enforcement_modes(policies, threat_level) do
    mode_adjustments = case threat_level do
      :critical -> %{monitor: :block, warn: :block, block: :quarantine}
      :high -> %{monitor: :warn, warn: :block}
      :medium -> %{monitor: :monitor}  # No change for medium
      :low -> %{block: :warn, quarantine: :block}
      :normal -> %{quarantine: :block, block: :warn}
    end
    
    Enum.into(policies, %{}, fn {id, policy} ->
      new_mode = Map.get(mode_adjustments, policy.enforcement_mode, policy.enforcement_mode)
      adapted_policy = %{policy | 
        enforcement_mode: new_mode,
        updated_at: DateTime.utc_now()
      }
      {id, adapted_policy}
    end)
  end
  
  defp rebuild_active_rules(policies) do
    policies
    |> Enum.filter(fn {_id, policy} -> policy.active end)
    |> Enum.flat_map(fn {_id, policy} -> 
      Enum.filter(policy.rules, & &1.enabled)
    end)
  end
  
  ## Private Functions - Utilities
  
  defp generate_policy_id do
    "policy_" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))
  end
  
  defp generate_rule_id do
    "rule_" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))
  end
  
  defp create_history_entry(action, policy) do
    %{
      action: action,
      policy_id: policy.id,
      policy_name: policy.name,
      version: policy.version,
      timestamp: DateTime.utc_now(),
      user: "system"  # Could be actual user in real implementation
    }
  end
  
  defp count_total_rules(policies) do
    policies
    |> Enum.map(fn {_id, policy} -> length(policy.rules) end)
    |> Enum.sum()
  end
  
  defp schedule_adaptive_update do
    Process.send_after(self(), :adaptive_policy_update, 600_000)  # 10 minutes
  end
  
  defp log_policy_evaluation(context, policies, actions) do
    Logger.debug("Policy evaluation completed", 
      context_keys: Map.keys(context),
      policies_matched: length(policies),
      actions_generated: length(actions)
    )
    
    # Record security event
    SecurityMonitor.record_event(%{
      type: :policy_evaluation,
      timestamp: DateTime.utc_now(),
      client_id: context[:client_id],
      metadata: %{
        policies_matched: length(policies),
        actions_generated: length(actions),
        action_types: Enum.map(actions, & &1.type)
      }
    })
  end
  
  ## Private Functions - Persistence
  
  defp load_policies do
    case Redis.get(@policy_store_key) do
      {:ok, nil} -> create_default_policies()
      {:ok, data} -> deserialize_policies(Jason.decode!(data))
      _ -> create_default_policies()
    end
  rescue
    _ -> create_default_policies()
  end
  
  defp load_active_rules do
    case Redis.get(@active_rules_key) do
      {:ok, nil} -> []
      {:ok, data} -> deserialize_rules(Jason.decode!(data))
      _ -> []
    end
  rescue
    _ -> []
  end
  
  defp load_policy_history do
    case Redis.get(@policy_history_key) do
      {:ok, nil} -> []
      {:ok, data} -> deserialize_history(Jason.decode!(data))
      _ -> []
    end
  rescue
    _ -> []
  end
  
  defp create_default_policies do
    # Create some basic default policies
    default_specs = [
      %{
        name: "Basic Rate Limiting",
        description: "Default rate limiting for all clients",
        rules: [
          %{
            name: "Global Rate Limit",
            type: :rate_limiting,
            actions: [%{type: :rate_limit, parameters: %{limit: 100, window: 60}}]
          }
        ]
      },
      %{
        name: "Admin Method Protection", 
        description: "Protect admin methods from unauthorized access",
        rules: [
          %{
            name: "Admin Method Guard",
            type: :access_control,
            conditions: [
              %{field: "method", operator: "matches", value: "lang\\.admin\\..*"}
            ],
            actions: [%{type: :require_admin_role, parameters: %{}}]
          }
        ]
      }
    ]
    
    Enum.into(default_specs, %{}, fn spec ->
      policy = create_policy_from_spec(spec)
      {policy.id, policy}
    end)
  end
  
  defp persist_policies(policies) do
    serialized = serialize_policies(policies) |> Jason.encode!()
    Redis.setex(@policy_store_key, 86400, serialized)
  end
  
  defp persist_active_rules(rules) do
    serialized = serialize_rules(rules) |> Jason.encode!()
    Redis.setex(@active_rules_key, 86400, serialized)
  end
  
  defp persist_policy_history(history) do
    serialized = serialize_history(history) |> Jason.encode!()
    Redis.setex(@policy_history_key, 86400, serialized)
  end
  
  defp serialize_policies(policies) do
    Enum.into(policies, %{}, fn {id, policy} ->
      {id, %{
        "id" => policy.id,
        "name" => policy.name,
        "description" => policy.description,
        "rules" => serialize_rules(policy.rules),
        "conditions" => policy.conditions,
        "enforcement_mode" => to_string(policy.enforcement_mode),
        "priority" => policy.priority,
        "created_at" => DateTime.to_iso8601(policy.created_at),
        "updated_at" => DateTime.to_iso8601(policy.updated_at),
        "version" => policy.version,
        "active" => policy.active
      }}
    end)
  end
  
  defp deserialize_policies(policies_data) do
    Enum.into(policies_data, %{}, fn {id, policy_data} ->
      {id, %{
        id: policy_data["id"],
        name: policy_data["name"],
        description: policy_data["description"],
        rules: deserialize_rules(policy_data["rules"]),
        conditions: policy_data["conditions"],
        enforcement_mode: String.to_atom(policy_data["enforcement_mode"]),
        priority: policy_data["priority"],
        created_at: DateTime.from_iso8601!(policy_data["created_at"]),
        updated_at: DateTime.from_iso8601!(policy_data["updated_at"]),
        version: policy_data["version"],
        active: policy_data["active"]
      }}
    end)
  end
  
  defp serialize_rules(rules) do
    Enum.map(rules, fn rule ->
      %{
        "id" => rule.id,
        "type" => to_string(rule.type),
        "name" => rule.name,
        "conditions" => rule.conditions,
        "actions" => rule.actions,
        "parameters" => rule.parameters,
        "enabled" => rule.enabled
      }
    end)
  end
  
  defp deserialize_rules(rules_data) do
    Enum.map(rules_data, fn rule_data ->
      %{
        id: rule_data["id"],
        type: String.to_atom(rule_data["type"]),
        name: rule_data["name"],
        conditions: rule_data["conditions"],
        actions: rule_data["actions"],
        parameters: rule_data["parameters"],
        enabled: rule_data["enabled"]
      }
    end)
  end
  
  defp serialize_history(history) do
    Enum.map(history, fn entry ->
      %{
        "action" => to_string(entry.action),
        "policy_id" => entry.policy_id,
        "policy_name" => entry.policy_name,
        "version" => entry.version,
        "timestamp" => DateTime.to_iso8601(entry.timestamp),
        "user" => entry.user
      }
    end)
  end
  
  defp deserialize_history(history_data) do
    Enum.map(history_data, fn entry_data ->
      %{
        action: String.to_atom(entry_data["action"]),
        policy_id: entry_data["policy_id"],
        policy_name: entry_data["policy_name"],
        version: entry_data["version"],
        timestamp: DateTime.from_iso8601!(entry_data["timestamp"]),
        user: entry_data["user"]
      }
    end)
  end
end