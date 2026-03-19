defmodule Lang.ML.AnomalyDetector do
  @moduledoc """
  ML-powered anomaly detection for MCP traffic using statistical and neural network approaches.

  Uses machine learning models to detect:
  - Unusual request patterns that may indicate attacks
  - Performance anomalies in tool execution
  - Abnormal usage spikes
  - Potential security threats in MCP communication

  Combines:
  - Statistical outlier detection (Isolation Forest, Z-score)
  - Neural network-based anomaly detection (Autoencoder)
  - Time-series analysis for pattern recognition

  Integrates with AshEvents for logging detected anomalies.
  """

  use GenServer
  require Logger

  alias Lang.Events
  alias Lang.ML.{FeatureExtractor, StatisticalDetector, NeuralDetector}

  # Model configuration
  @threshold 0.7  # Anomaly score threshold
  @training_interval :timer.hours(24)  # Retrain every 24 hours
  @max_training_samples 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    # Initialize ML components
    state = %{
      statistical_detector: StatisticalDetector.new(),
      neural_detector: NeuralDetector.new(),
      feature_extractor: FeatureExtractor.new(),
      training_data: [],
      anomaly_count: 0,
      normal_count: 0,
      last_training: nil,
      model_performance: %{}
    }

    # Schedule initial training
    Process.send_after(self(), :train_models, :timer.seconds(30))

    # Schedule periodic retraining
    Process.send_after(self(), :periodic_training, @training_interval)

    {:ok, state}
  end

  @doc """
  Analyze MCP request for anomalies using ensemble approach.

  Returns {:ok, :normal} or {:anomaly, score, details}
  """
  def analyze_request(request, user_id, session_id) do
    GenServer.call(__MODULE__, {:analyze_request, request, user_id, session_id})
  end

  @doc """
  Add training sample for model improvement.
  """
  def add_training_sample(request, label) do
    GenServer.cast(__MODULE__, {:add_training_sample, request, label})
  end

  @doc """
  Force retrain models with current training data.
  """
  def retrain_models do
    GenServer.call(__MODULE__, :retrain_models)
  end

  @doc """
  Get detailed anomaly statistics and model performance.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server callbacks

  def handle_call({:analyze_request, request, user_id, session_id}, _from, state) do
    try do
      # Extract features from request
      features = FeatureExtractor.extract_features(state.feature_extractor, request)

      # Get anomaly scores from both detectors
      statistical_score = StatisticalDetector.score(state.statistical_detector, features)
      neural_score = NeuralDetector.score(state.neural_detector, features)

      # Ensemble scoring (weighted average)
      ensemble_score = (statistical_score * 0.6) + (neural_score * 0.4)

      # Determine if anomalous
      is_anomalous = ensemble_score > @threshold

      result = if is_anomalous do
        # Log anomaly with detailed information
        Events.track_event(%{
          event_type: "mcp_anomaly_detected",
          user_id: user_id,
          metadata: %{
            session_id: session_id,
            ensemble_score: ensemble_score,
            statistical_score: statistical_score,
            neural_score: neural_score,
            request_features: features,
            detection_method: "ensemble_ml",
            timestamp: DateTime.utc_now()
          }
        })

        {:anomaly, ensemble_score, %{
          reason: "High anomaly score detected",
          ensemble_score: ensemble_score,
          statistical_score: statistical_score,
          neural_score: neural_score,
          features: features,
          confidence: calculate_confidence(ensemble_score)
        }}
      else
        :normal
      end

      # Update counters
      new_state = if is_anomalous do
        %{state | anomaly_count: state.anomaly_count + 1}
      else
        %{state | normal_count: state.normal_count + 1}
      end

      {:reply, result, new_state}

    rescue
      e ->
        Logger.error("Error in anomaly detection", error: e, request: inspect(request))
        {:reply, :normal, state}
    end
  end

  def handle_call(:retrain_models, _from, state) do
    Logger.info("Retraining ML models with #{length(state.training_data)} samples")

    try do
      # Retrain statistical detector
      new_statistical = StatisticalDetector.train(state.statistical_detector, state.training_data)

      # Retrain neural detector
      new_neural = NeuralDetector.train(state.neural_detector, state.training_data)

      # Calculate performance metrics
      performance = evaluate_model_performance(state.training_data, new_statistical, new_neural)

      new_state = %{
        state |
        statistical_detector: new_statistical,
        neural_detector: new_neural,
        last_training: DateTime.utc_now(),
        model_performance: performance
      }

      Logger.info("ML models retrained successfully", performance: performance)
      {:reply, :ok, new_state}

    rescue
      e ->
        Logger.error("Failed to retrain ML models", error: e)
        {:reply, {:error, "Retraining failed"}, state}
    end
  end

  def handle_call(:stats, _from, state) do
    total_samples = state.anomaly_count + state.normal_count
    anomaly_rate = if total_samples > 0, do: state.anomaly_count / total_samples, else: 0

    stats = %{
      anomaly_count: state.anomaly_count,
      normal_count: state.normal_count,
      total_samples: total_samples,
      anomaly_rate: anomaly_rate,
      training_samples: length(state.training_data),
      last_training: state.last_training,
      model_performance: state.model_performance,
      detectors: %{
        statistical: StatisticalDetector.stats(state.statistical_detector),
        neural: NeuralDetector.stats(state.neural_detector)
      }
    }

    {:reply, stats, state}
  end

  def handle_cast({:add_training_sample, request, label}, state) do
    # Add sample to training data
    sample = %{
      features: FeatureExtractor.extract_features(state.feature_extractor, request),
      label: label,
      timestamp: DateTime.utc_now()
    }

    # Keep only recent samples (LRU)
    new_training_data = ([sample | state.training_data])
    |> Enum.take(@max_training_samples)

    {:noreply, %{state | training_data: new_training_data}}
  end

  def handle_info(:train_models, state) do
    # Initial training with synthetic data if no real data available
    training_data = if state.training_data == [] do
      generate_synthetic_training_data()
    else
      state.training_data
    end

    # Train models
    new_statistical = StatisticalDetector.train(state.statistical_detector, training_data)
    new_neural = NeuralDetector.train(state.neural_detector, training_data)

    new_state = %{
      state |
      statistical_detector: new_statistical,
      neural_detector: new_neural,
      last_training: DateTime.utc_now()
    }

    {:noreply, new_state}
  end

  def handle_info(:periodic_training, state) do
    # Retrain with accumulated data
    if length(state.training_data) >= 100 do
      {:noreply, new_state} = handle_call(:retrain_models, nil, state)
      # Schedule next training
      Process.send_after(self(), :periodic_training, @training_interval)
      {:noreply, new_state}
    else
      # Not enough data, try again later
      Process.send_after(self(), :periodic_training, @training_interval)
      {:noreply, state}
    end
  end

  # Private functions

  defp calculate_confidence(score) do
    # Convert score to confidence percentage
    min(100, max(0, round((score - @threshold) / (1 - @threshold) * 100)))
  end

  defp evaluate_model_performance(training_data, statistical_detector, neural_detector) do
    # Simple cross-validation
    test_samples = Enum.take_random(training_data, min(100, length(training_data)))

    statistical_scores = Enum.map(test_samples, fn sample ->
      StatisticalDetector.score(statistical_detector, sample.features)
    end)

    neural_scores = Enum.map(test_samples, fn sample ->
      NeuralDetector.score(neural_detector, sample.features)
    end)

    %{
      statistical_accuracy: calculate_accuracy(statistical_scores, test_samples),
      neural_accuracy: calculate_accuracy(neural_scores, test_samples),
      ensemble_accuracy: calculate_ensemble_accuracy(statistical_scores, neural_scores, test_samples)
    }
  end

  defp calculate_accuracy(scores, samples) do
    predictions = Enum.map(scores, &(&1 > @threshold))
    actuals = Enum.map(samples, &(&1.label == :anomaly))

    correct = Enum.zip(predictions, actuals)
    |> Enum.count(fn {pred, actual} -> pred == actual end)

    correct / length(samples)
  end

  defp calculate_ensemble_accuracy(statistical_scores, neural_scores, samples) do
    ensemble_scores = Enum.zip(statistical_scores, neural_scores)
    |> Enum.map(fn {s, n} -> (s * 0.6) + (n * 0.4) end)

    calculate_accuracy(ensemble_scores, samples)
  end

  defp generate_synthetic_training_data do
    # Generate synthetic training data for initial model training
    Enum.map(1..500, fn _ ->
      # Generate normal request features
      is_anomaly = :rand.uniform() < 0.1  # 10% anomalies

      features = if is_anomaly do
        # Anomalous features
        %{
          request_size: :rand.uniform(10000) + 5000,  # Larger requests
          tool_count: :rand.uniform(50) + 10,         # More tools
          param_complexity: :rand.uniform(5000) + 1000,
          timestamp_hour: :rand.uniform(24),
          has_suspicious_patterns: true,
          nested_depth: :rand.uniform(10) + 5
        }
      else
        # Normal features
        %{
          request_size: :rand.uniform(1000) + 100,
          tool_count: :rand.uniform(5) + 1,
          param_complexity: :rand.uniform(500) + 50,
          timestamp_hour: :rand.uniform(24),
          has_suspicious_patterns: false,
          nested_depth: :rand.uniform(3) + 1
        }
      end

      %{
        features: features,
        label: if(is_anomaly, do: :anomaly, else: :normal),
        timestamp: DateTime.utc_now()
      }
    end)
  end
end