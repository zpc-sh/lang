defmodule Lang.Security.ThreatIntelligence do
  @moduledoc """
  Advanced threat intelligence system for adaptive security.
  
  This system:
  - Analyzes attack patterns and learns from security events
  - Maintains threat intelligence feeds and IOCs (Indicators of Compromise)
  - Provides predictive threat scoring and risk assessment
  - Adapts security policies based on emerging threats
  - Integrates with external threat intelligence sources
  """
  
  use GenServer
  require Logger
  
  alias Lang.Monitoring.SecurityMonitor
  alias Lang.Security.RedisLimiter
  alias Lang.Redis
  
  @threat_intel_key "threat_intelligence"
  @ioc_key "indicators_of_compromise"
  @attack_patterns_key "attack_patterns"
  @adaptive_rules_key "adaptive_security_rules"
  
  # Threat score thresholds
  @low_threat_threshold 25
  @medium_threat_threshold 50  
  @high_threat_threshold 75
  @critical_threat_threshold 90
  
  # Learning parameters
  @pattern_memory_days 30
  @min_events_for_pattern 5
  @confidence_threshold 0.7
  
  @type threat_level :: :low | :medium | :high | :critical
  @type ioc :: %{
    type: :ip | :client_id | :method | :pattern,
    value: String.t(),
    threat_score: float(),
    first_seen: DateTime.t(),
    last_seen: DateTime.t(),
    confidence: float(),
    source: String.t()
  }
  
  @type attack_pattern :: %{
    pattern_id: String.t(),
    description: String.t(),
    indicators: [ioc()],
    frequency: integer(),
    severity: threat_level(),
    tactics: [String.t()],
    techniques: [String.t()],
    confidence: float()
  }
  
  defstruct [
    :threat_feeds,
    :iocs,
    :attack_patterns,
    :adaptive_rules,
    :ml_model_state,
    :last_analysis,
    :stats
  ]
  
  ## Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Analyzes a security event and updates threat intelligence.
  """
  @spec analyze_event(map()) :: {:ok, map()} | {:error, term()}
  def analyze_event(event) do
    GenServer.call(__MODULE__, {:analyze_event, event})
  end
  
  @doc """
  Gets threat score for a client, IP, or other identifier.
  """
  @spec get_threat_score(String.t(), atom()) :: float()
  def get_threat_score(identifier, type \\ :client_id) do
    GenServer.call(__MODULE__, {:get_threat_score, identifier, type})
  end
  
  @doc """
  Checks if an indicator is flagged as suspicious.
  """
  @spec is_suspicious?(String.t(), atom()) :: boolean()
  def is_suspicious?(value, type) do
    GenServer.call(__MODULE__, {:is_suspicious, value, type})
  end
  
  @doc """
  Gets current threat intelligence summary.
  """
  @spec get_threat_summary() :: map()
  def get_threat_summary do
    GenServer.call(__MODULE__, :get_threat_summary)
  end
  
  @doc """
  Forces a machine learning model update based on recent events.
  """
  @spec update_ml_model() :: :ok | {:error, term()}
  def update_ml_model do
    GenServer.call(__MODULE__, :update_ml_model, 30_000)
  end
  
  @doc """
  Adds external threat intelligence feed data.
  """
  @spec ingest_threat_feed(String.t(), [map()]) :: :ok | {:error, term()}
  def ingest_threat_feed(feed_name, indicators) do
    GenServer.call(__MODULE__, {:ingest_threat_feed, feed_name, indicators})
  end
  
  @doc """
  Gets adaptive security recommendations based on current threats.
  """
  @spec get_adaptive_recommendations() :: [map()]
  def get_adaptive_recommendations do
    GenServer.call(__MODULE__, :get_adaptive_recommendations)
  end
  
  ## GenServer Implementation
  
  def init(_opts) do
    # Load persisted threat intelligence
    state = %__MODULE__{
      threat_feeds: load_threat_feeds(),
      iocs: load_iocs(),
      attack_patterns: load_attack_patterns(),
      adaptive_rules: load_adaptive_rules(),
      ml_model_state: initialize_ml_model(),
      last_analysis: DateTime.utc_now(),
      stats: %{
        events_analyzed: 0,
        threats_detected: 0,
        patterns_learned: 0,
        model_updates: 0
      }
    }
    
    # Schedule periodic analysis
    schedule_analysis()
    
    Logger.info("Threat Intelligence system initialized")
    {:ok, state}
  end
  
  def handle_call({:analyze_event, event}, _from, state) do
    # Extract features from the event
    features = extract_event_features(event)
    
    # Check against known IOCs
    ioc_matches = check_ioc_matches(features, state.iocs)
    
    # Check against attack patterns
    pattern_matches = check_pattern_matches(features, state.attack_patterns)
    
    # Calculate threat score
    threat_score = calculate_threat_score(features, ioc_matches, pattern_matches, state.ml_model_state)
    
    # Update IOCs and patterns if needed
    new_state = update_intelligence(state, event, features, threat_score)
    
    # Generate analysis result
    analysis_result = %{
      threat_score: threat_score,
      threat_level: categorize_threat_level(threat_score),
      ioc_matches: ioc_matches,
      pattern_matches: pattern_matches,
      recommendations: generate_event_recommendations(threat_score, ioc_matches, pattern_matches)
    }
    
    # Update statistics
    updated_stats = %{
      new_state.stats | 
      events_analyzed: new_state.stats.events_analyzed + 1,
      threats_detected: new_state.stats.threats_detected + if(threat_score > @medium_threat_threshold, do: 1, else: 0)
    }
    
    final_state = %{new_state | stats: updated_stats}
    
    {:reply, {:ok, analysis_result}, final_state}
  end
  
  def handle_call({:get_threat_score, identifier, type}, _from, state) do
    score = case Map.get(state.iocs, {type, identifier}) do
      nil -> 0.0
      ioc -> ioc.threat_score
    end
    
    {:reply, score, state}
  end
  
  def handle_call({:is_suspicious, value, type}, _from, state) do
    suspicious = case Map.get(state.iocs, {type, value}) do
      nil -> false
      ioc -> ioc.threat_score > @low_threat_threshold and ioc.confidence > @confidence_threshold
    end
    
    {:reply, suspicious, state}
  end
  
  def handle_call(:get_threat_summary, _from, state) do
    summary = %{
      total_iocs: map_size(state.iocs),
      attack_patterns: length(state.attack_patterns),
      threat_feeds: map_size(state.threat_feeds),
      adaptive_rules: length(state.adaptive_rules),
      last_analysis: state.last_analysis,
      stats: state.stats,
      top_threats: get_top_threats(state.iocs, 10),
      recent_patterns: get_recent_patterns(state.attack_patterns, 5)
    }
    
    {:reply, summary, state}
  end
  
  def handle_call(:update_ml_model, _from, state) do
    Logger.info("Updating machine learning model...")
    
    try do
      # Collect recent training data
      training_data = collect_training_data()
      
      # Update the model
      updated_model_state = train_ml_model(state.ml_model_state, training_data)
      
      # Update statistics
      updated_stats = %{state.stats | model_updates: state.stats.model_updates + 1}
      
      new_state = %{state | 
        ml_model_state: updated_model_state,
        stats: updated_stats
      }
      
      # Persist updated model
      persist_ml_model(updated_model_state)
      
      Logger.info("Machine learning model updated successfully")
      {:reply, :ok, new_state}
    rescue
      error ->
        Logger.error("Failed to update ML model: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end
  
  def handle_call({:ingest_threat_feed, feed_name, indicators}, _from, state) do
    Logger.info("Ingesting threat feed: #{feed_name}", count: length(indicators))
    
    # Process and normalize indicators
    processed_indicators = Enum.map(indicators, &process_external_indicator(&1, feed_name))
    
    # Update IOCs with new indicators
    new_iocs = Enum.reduce(processed_indicators, state.iocs, fn indicator, acc ->
      Map.put(acc, {indicator.type, indicator.value}, indicator)
    end)
    
    # Update threat feeds registry
    new_feeds = Map.put(state.threat_feeds, feed_name, %{
      last_updated: DateTime.utc_now(),
      indicator_count: length(indicators)
    })
    
    new_state = %{state | iocs: new_iocs, threat_feeds: new_feeds}
    
    # Persist updates
    persist_iocs(new_iocs)
    persist_threat_feeds(new_feeds)
    
    {:reply, :ok, new_state}
  end
  
  def handle_call(:get_adaptive_recommendations, _from, state) do
    recommendations = generate_adaptive_recommendations(state)
    {:reply, recommendations, state}
  end
  
  def handle_info(:periodic_analysis, state) do
    # Schedule next analysis
    schedule_analysis()
    
    # Perform periodic threat intelligence analysis
    new_state = perform_periodic_analysis(state)
    
    {:noreply, new_state}
  end
  
  ## Private Functions - Feature Extraction
  
  defp extract_event_features(event) do
    %{
      client_id: event[:client_id],
      method: event[:method],
      ip_address: get_in(event, [:metadata, :ip_address]),
      user_agent: get_in(event, [:metadata, :user_agent]),
      session_id: get_in(event, [:metadata, :session_id]),
      timestamp: event[:timestamp] || DateTime.utc_now(),
      event_type: event[:type],
      params_structure: analyze_params_structure(event[:params] || %{}),
      request_size: estimate_request_size(event),
      anomaly_indicators: detect_anomaly_indicators(event)
    }
  end
  
  defp analyze_params_structure(params) when is_map(params) do
    %{
      key_count: map_size(params),
      has_nested_objects: has_nested_maps?(params),
      suspicious_keys: find_suspicious_keys(params),
      data_types: analyze_value_types(params)
    }
  end
  defp analyze_params_structure(_), do: %{key_count: 0}
  
  defp has_nested_maps?(params) do
    Enum.any?(params, fn {_k, v} -> is_map(v) end)
  end
  
  defp find_suspicious_keys(params) do
    suspicious_patterns = [
      ~r/script/i, ~r/exec/i, ~r/eval/i, ~r/system/i,
      ~r/cmd/i, ~r/command/i, ~r/shell/i, ~r/\.\./, 
      ~r/passwd/i, ~r/shadow/i, ~r/etc/i
    ]
    
    Enum.filter(Map.keys(params), fn key ->
      key_str = to_string(key)
      Enum.any?(suspicious_patterns, &Regex.match?(&1, key_str))
    end)
  end
  
  defp analyze_value_types(params) do
    Enum.reduce(params, %{}, fn {_k, v}, acc ->
      type = get_value_type(v)
      Map.update(acc, type, 1, &(&1 + 1))
    end)
  end
  
  defp get_value_type(value) do
    cond do
      is_binary(value) -> :string
      is_integer(value) -> :integer
      is_float(value) -> :float
      is_boolean(value) -> :boolean
      is_list(value) -> :list
      is_map(value) -> :map
      true -> :other
    end
  end
  
  defp estimate_request_size(event) do
    try do
      event |> Jason.encode!() |> byte_size()
    rescue
      _ -> 0
    end
  end
  
  defp detect_anomaly_indicators(event) do
    indicators = []
    
    # Check for unusual timing patterns
    indicators = if rapid_requests?(event), do: [:rapid_requests | indicators], else: indicators
    
    # Check for suspicious parameter patterns
    indicators = if has_injection_patterns?(event), do: [:injection_patterns | indicators], else: indicators
    
    # Check for unusual method usage
    indicators = if unusual_method?(event), do: [:unusual_method | indicators], else: indicators
    
    indicators
  end
  
  defp rapid_requests?(event) do
    # Would check for rapid request patterns
    false
  end
  
  defp has_injection_patterns?(event) do
    params_str = inspect(event[:params] || %{})
    injection_patterns = [
      ~r/union\s+select/i,
      ~r/or\s+1\s*=\s*1/i,
      ~r/<script/i,
      ~r/javascript:/i,
      ~r/\.\.\//,
      ~r/cmd\.exe/i
    ]
    
    Enum.any?(injection_patterns, &Regex.match?(&1, params_str))
  end
  
  defp unusual_method?(event) do
    method = event[:method]
    # Check against list of rarely used methods
    rare_methods = ["lang.admin.shutdown", "lang.debug.dump", "lang.system.exec"]
    method in rare_methods
  end
  
  ## Private Functions - IOC and Pattern Matching
  
  defp check_ioc_matches(features, iocs) do
    potential_matches = [
      {features.client_id, :client_id},
      {features.ip_address, :ip},
      {features.method, :method},
      {features.user_agent, :user_agent}
    ]
    
    Enum.reduce(potential_matches, [], fn {value, type}, matches ->
      case value do
        nil -> matches
        val ->
          case Map.get(iocs, {type, val}) do
            nil -> matches
            ioc -> [ioc | matches]
          end
      end
    end)
  end
  
  defp check_pattern_matches(features, attack_patterns) do
    Enum.filter(attack_patterns, fn pattern ->
      match_pattern?(features, pattern)
    end)
  end
  
  defp match_pattern?(features, pattern) do
    # Simple pattern matching - in production this would be more sophisticated
    matching_indicators = Enum.count(pattern.indicators, fn indicator ->
      case indicator.type do
        :client_id -> indicator.value == features.client_id
        :ip -> indicator.value == features.ip_address
        :method -> indicator.value == features.method
        :pattern -> pattern_matches_feature?(indicator.value, features)
      end
    end)
    
    # Pattern matches if at least 50% of indicators match
    matching_indicators >= length(pattern.indicators) * 0.5
  end
  
  defp pattern_matches_feature?(pattern_value, features) do
    # Check if pattern matches any feature
    feature_strings = [
      features.method,
      features.user_agent,
      inspect(features.params_structure),
      inspect(features.anomaly_indicators)
    ]
    
    Enum.any?(feature_strings, fn str ->
      str && String.contains?(String.downcase(str), String.downcase(pattern_value))
    end)
  end
  
  ## Private Functions - Threat Scoring
  
  defp calculate_threat_score(features, ioc_matches, pattern_matches, ml_model_state) do
    base_score = 0.0
    
    # IOC-based scoring
    ioc_score = Enum.reduce(ioc_matches, 0.0, fn ioc, acc ->
      acc + (ioc.threat_score * ioc.confidence)
    end)
    
    # Pattern-based scoring
    pattern_score = Enum.reduce(pattern_matches, 0.0, fn pattern, acc ->
      severity_multiplier = case pattern.severity do
        :low -> 10
        :medium -> 25
        :high -> 50
        :critical -> 75
      end
      acc + (severity_multiplier * pattern.confidence)
    end)
    
    # Anomaly-based scoring
    anomaly_score = length(features.anomaly_indicators) * 15
    
    # ML model scoring
    ml_score = calculate_ml_score(features, ml_model_state)
    
    # Combine scores (weighted average)
    total_score = base_score + ioc_score + pattern_score + anomaly_score + ml_score
    
    # Normalize to 0-100 range
    min(100.0, max(0.0, total_score))
  end
  
  defp calculate_ml_score(features, ml_model_state) do
    # Simple ML scoring based on feature analysis
    # In production, this would use a trained ML model
    score = 0.0
    
    # Score based on suspicious key patterns
    score = score + (length(features.params_structure[:suspicious_keys] || []) * 10)
    
    # Score based on request size
    if features.request_size > 100_000 do
      score = score + 20
    end
    
    # Score based on anomaly indicators
    score = score + (length(features.anomaly_indicators) * 15)
    
    score
  end
  
  defp categorize_threat_level(score) do
    cond do
      score >= @critical_threat_threshold -> :critical
      score >= @high_threat_threshold -> :high
      score >= @medium_threat_threshold -> :medium
      score >= @low_threat_threshold -> :low
      true -> :minimal
    end
  end
  
  ## Private Functions - Intelligence Updates
  
  defp update_intelligence(state, event, features, threat_score) do
    new_state = state
    
    # Update IOCs if threat score is significant
    new_state = if threat_score > @low_threat_threshold do
      update_iocs(new_state, features, threat_score)
    else
      new_state
    end
    
    # Learn new attack patterns
    new_state = if threat_score > @medium_threat_threshold do
      learn_attack_pattern(new_state, event, features, threat_score)
    else
      new_state
    end
    
    %{new_state | last_analysis: DateTime.utc_now()}
  end
  
  defp update_iocs(state, features, threat_score) do
    updates = [
      {features.client_id, :client_id},
      {features.ip_address, :ip},
      {features.method, :method}
    ]
    
    new_iocs = Enum.reduce(updates, state.iocs, fn {value, type}, acc ->
      case value do
        nil -> acc
        val ->
          existing = Map.get(acc, {type, val})
          updated_ioc = create_or_update_ioc(existing, type, val, threat_score)
          Map.put(acc, {type, val}, updated_ioc)
      end
    end)
    
    %{state | iocs: new_iocs}
  end
  
  defp create_or_update_ioc(nil, type, value, threat_score) do
    %{
      type: type,
      value: value,
      threat_score: threat_score,
      first_seen: DateTime.utc_now(),
      last_seen: DateTime.utc_now(),
      confidence: 0.5,
      source: "internal_analysis"
    }
  end
  
  defp create_or_update_ioc(existing_ioc, _type, _value, threat_score) do
    # Update existing IOC with new information
    %{existing_ioc |
      threat_score: (existing_ioc.threat_score + threat_score) / 2,
      last_seen: DateTime.utc_now(),
      confidence: min(1.0, existing_ioc.confidence + 0.1)
    }
  end
  
  defp learn_attack_pattern(state, event, features, threat_score) do
    # Create a simple attack pattern based on the event
    pattern = %{
      pattern_id: generate_pattern_id(event, features),
      description: "Learned pattern from suspicious activity",
      indicators: create_pattern_indicators(features),
      frequency: 1,
      severity: categorize_threat_level(threat_score),
      tactics: infer_attack_tactics(features),
      techniques: infer_attack_techniques(features),
      confidence: 0.6
    }
    
    # Check if similar pattern exists
    existing_pattern = find_similar_pattern(state.attack_patterns, pattern)
    
    new_patterns = if existing_pattern do
      # Update existing pattern
      update_existing_pattern(state.attack_patterns, existing_pattern, pattern)
    else
      # Add new pattern
      [pattern | state.attack_patterns]
    end
    
    updated_stats = %{state.stats | patterns_learned: state.stats.patterns_learned + 1}
    
    %{state | attack_patterns: new_patterns, stats: updated_stats}
  end
  
  defp generate_pattern_id(event, features) do
    # Create a unique pattern ID based on key characteristics
    base_string = "#{event[:type]}_#{features.method}_#{length(features.anomaly_indicators)}"
    :crypto.hash(:sha256, base_string) |> Base.encode16() |> String.slice(0, 16)
  end
  
  defp create_pattern_indicators(features) do
    indicators = []
    
    if features.client_id do
      indicators = [%{type: :client_id, value: features.client_id} | indicators]
    end
    
    if features.method do
      indicators = [%{type: :method, value: features.method} | indicators]
    end
    
    if features.anomaly_indicators != [] do
      indicators = [%{type: :pattern, value: "anomaly_indicators"} | indicators]
    end
    
    indicators
  end
  
  defp infer_attack_tactics(features) do
    tactics = []
    
    tactics = if :injection_patterns in features.anomaly_indicators do
      ["Initial Access", "Execution" | tactics]
    else
      tactics
    end
    
    tactics = if :rapid_requests in features.anomaly_indicators do
      ["Impact" | tactics]
    else
      tactics
    end
    
    tactics
  end
  
  defp infer_attack_techniques(features) do
    techniques = []
    
    if features.params_structure[:suspicious_keys] != [] do
      techniques = ["T1059 - Command and Scripting Interpreter" | techniques]
    end
    
    if :injection_patterns in features.anomaly_indicators do
      techniques = ["T1190 - Exploit Public-Facing Application" | techniques]
    end
    
    techniques
  end
  
  defp find_similar_pattern(patterns, new_pattern) do
    Enum.find(patterns, fn existing ->
      similarity_score(existing, new_pattern) > 0.8
    end)
  end
  
  defp similarity_score(pattern1, pattern2) do
    # Simple similarity calculation based on shared indicators
    indicators1 = MapSet.new(pattern1.indicators, &{&1.type, &1.value})
    indicators2 = MapSet.new(pattern2.indicators, &{&1.type, &1.value})
    
    intersection = MapSet.intersection(indicators1, indicators2) |> MapSet.size()
    union = MapSet.union(indicators1, indicators2) |> MapSet.size()
    
    if union > 0, do: intersection / union, else: 0.0
  end
  
  defp update_existing_pattern(patterns, existing_pattern, new_pattern) do
    Enum.map(patterns, fn pattern ->
      if pattern.pattern_id == existing_pattern.pattern_id do
        %{pattern |
          frequency: pattern.frequency + 1,
          confidence: min(1.0, pattern.confidence + 0.05)
        }
      else
        pattern
      end
    end)
  end
  
  ## Private Functions - Recommendations
  
  defp generate_event_recommendations(threat_score, ioc_matches, pattern_matches) do
    recommendations = []
    
    recommendations = if threat_score > @high_threat_threshold do
      ["Block client immediately", "Escalate to security team" | recommendations]
    else
      recommendations
    end
    
    recommendations = if length(ioc_matches) > 0 do
      ["Increase monitoring for matched IOCs" | recommendations]
    else
      recommendations
    end
    
    recommendations = if length(pattern_matches) > 0 do
      ["Apply additional validation rules" | recommendations]
    else
      recommendations
    end
    
    Enum.reverse(recommendations)
  end
  
  defp generate_adaptive_recommendations(state) do
    recommendations = []
    
    # Analyze top threats
    top_threats = get_top_threats(state.iocs, 5)
    if length(top_threats) > 0 do
      recommendations = [
        %{
          type: :rate_limiting,
          priority: :high,
          description: "Implement stricter rate limits for high-threat indicators",
          indicators: Enum.map(top_threats, & &1.value)
        }
        | recommendations
      ]
    end
    
    # Analyze attack patterns
    if length(state.attack_patterns) > 0 do
      recommendations = [
        %{
          type: :validation_rules,
          priority: :medium,
          description: "Create custom validation rules based on learned attack patterns",
          patterns: Enum.map(state.attack_patterns, & &1.pattern_id)
        }
        | recommendations
      ]
    end
    
    recommendations
  end
  
  ## Private Functions - Utilities
  
  defp schedule_analysis do
    Process.send_after(self(), :periodic_analysis, 300_000)  # 5 minutes
  end
  
  defp perform_periodic_analysis(state) do
    Logger.debug("Performing periodic threat intelligence analysis")
    
    # Clean up old IOCs
    cutoff_time = DateTime.add(DateTime.utc_now(), -@pattern_memory_days * 24 * 3600)
    new_iocs = Enum.filter(state.iocs, fn {_key, ioc} ->
      DateTime.compare(ioc.last_seen, cutoff_time) == :gt
    end) |> Enum.into(%{})
    
    # Update confidence scores based on age
    aged_iocs = Enum.into(new_iocs, %{}, fn {key, ioc} ->
      age_days = DateTime.diff(DateTime.utc_now(), ioc.last_seen, :day)
      confidence_decay = max(0.1, 1.0 - (age_days * 0.01))
      aged_ioc = %{ioc | confidence: ioc.confidence * confidence_decay}
      {key, aged_ioc}
    end)
    
    %{state | iocs: aged_iocs}
  end
  
  defp get_top_threats(iocs, limit) do
    iocs
    |> Enum.map(fn {_key, ioc} -> ioc end)
    |> Enum.sort_by(& &1.threat_score, :desc)
    |> Enum.take(limit)
  end
  
  defp get_recent_patterns(patterns, limit) do
    # Would sort by recency - for now just take first N
    Enum.take(patterns, limit)
  end
  
  defp process_external_indicator(indicator, feed_name) do
    %{
      type: normalize_indicator_type(indicator["type"]),
      value: indicator["value"],
      threat_score: indicator["threat_score"] || 50.0,
      first_seen: parse_timestamp(indicator["first_seen"]) || DateTime.utc_now(),
      last_seen: parse_timestamp(indicator["last_seen"]) || DateTime.utc_now(),
      confidence: indicator["confidence"] || 0.7,
      source: feed_name
    }
  end
  
  defp normalize_indicator_type(type_string) do
    case String.downcase(type_string) do
      "ip" -> :ip
      "domain" -> :domain
      "url" -> :url
      "hash" -> :hash
      "client_id" -> :client_id
      _ -> :other
    end
  end
  
  defp parse_timestamp(nil), do: nil
  defp parse_timestamp(timestamp_str) do
    case DateTime.from_iso8601(timestamp_str) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end
  
  ## Private Functions - Persistence
  
  defp load_threat_feeds do
    case Redis.get(@threat_intel_key <> ":feeds") do
      {:ok, nil} -> %{}
      {:ok, data} -> Jason.decode!(data) |> deserialize_feeds()
      _ -> %{}
    end
  rescue
    _ -> %{}
  end
  
  defp load_iocs do
    case Redis.get(@ioc_key) do
      {:ok, nil} -> %{}
      {:ok, data} -> Jason.decode!(data) |> deserialize_iocs()
      _ -> %{}
    end
  rescue
    _ -> %{}
  end
  
  defp load_attack_patterns do
    case Redis.get(@attack_patterns_key) do
      {:ok, nil} -> []
      {:ok, data} -> Jason.decode!(data) |> deserialize_patterns()
      _ -> []
    end
  rescue
    _ -> []
  end
  
  defp load_adaptive_rules do
    case Redis.get(@adaptive_rules_key) do
      {:ok, nil} -> []
      {:ok, data} -> Jason.decode!(data)
      _ -> []
    end
  rescue
    _ -> []
  end
  
  defp persist_threat_feeds(feeds) do
    serialized = serialize_feeds(feeds) |> Jason.encode!()
    Redis.setex(@threat_intel_key <> ":feeds", 86400, serialized)
  end
  
  defp persist_iocs(iocs) do
    serialized = serialize_iocs(iocs) |> Jason.encode!()
    Redis.setex(@ioc_key, 86400, serialized)
  end
  
  defp serialize_feeds(feeds) do
    Enum.into(feeds, %{}, fn {name, feed_data} ->
      {name, %{
        "last_updated" => DateTime.to_iso8601(feed_data.last_updated),
        "indicator_count" => feed_data.indicator_count
      }}
    end)
  end
  
  defp deserialize_feeds(feeds_data) do
    Enum.into(feeds_data, %{}, fn {name, feed_data} ->
      {name, %{
        last_updated: DateTime.from_iso8601!(feed_data["last_updated"]),
        indicator_count: feed_data["indicator_count"]
      }}
    end)
  end
  
  defp serialize_iocs(iocs) do
    Enum.into(iocs, %{}, fn {{type, value}, ioc} ->
      {"#{type}:#{value}", %{
        "type" => to_string(ioc.type),
        "value" => ioc.value,
        "threat_score" => ioc.threat_score,
        "first_seen" => DateTime.to_iso8601(ioc.first_seen),
        "last_seen" => DateTime.to_iso8601(ioc.last_seen),
        "confidence" => ioc.confidence,
        "source" => ioc.source
      }}
    end)
  end
  
  defp deserialize_iocs(iocs_data) do
    Enum.into(iocs_data, %{}, fn {key, ioc_data} ->
      [type_str, value] = String.split(key, ":", parts: 2)
      type = String.to_atom(type_str)
      
      ioc = %{
        type: type,
        value: value,
        threat_score: ioc_data["threat_score"],
        first_seen: DateTime.from_iso8601!(ioc_data["first_seen"]),
        last_seen: DateTime.from_iso8601!(ioc_data["last_seen"]),
        confidence: ioc_data["confidence"],
        source: ioc_data["source"]
      }
      
      {{type, value}, ioc}
    end)
  end
  
  defp deserialize_patterns(patterns_data) do
    Enum.map(patterns_data, fn pattern_data ->
      %{
        pattern_id: pattern_data["pattern_id"],
        description: pattern_data["description"],
        indicators: pattern_data["indicators"],
        frequency: pattern_data["frequency"],
        severity: String.to_atom(pattern_data["severity"]),
        tactics: pattern_data["tactics"],
        techniques: pattern_data["techniques"],
        confidence: pattern_data["confidence"]
      }
    end)
  end
  
  ## Private Functions - Machine Learning
  
  defp initialize_ml_model do
    # Initialize a simple ML model state
    %{
      feature_weights: %{
        suspicious_keys: 1.0,
        request_size: 0.5,
        anomaly_count: 1.2,
        method_rarity: 0.8
      },
      training_iterations: 0,
      last_updated: DateTime.utc_now()
    }
  end
  
  defp collect_training_data do
    # Would collect recent security events for training
    # For now, return empty list
    []
  end
  
  defp train_ml_model(current_state, training_data) do
    # Simple model training simulation
    # In production, this would use a proper ML library
    %{current_state |
      training_iterations: current_state.training_iterations + 1,
      last_updated: DateTime.utc_now()
    }
  end
  
  defp persist_ml_model(model_state) do
    serialized = Jason.encode!(model_state)
    Redis.setex("ml_model_state", 86400, serialized)
  end
end