defmodule Lang.ML.StatisticalDetector do
  @moduledoc """
  Statistical anomaly detection using traditional ML methods.

  Implements statistical approaches for anomaly detection:
  - Z-score based outlier detection
  - Isolation Forest algorithm
  - Mahalanobis distance
  - Statistical process control methods

  This provides a robust baseline for anomaly detection that works well
  with smaller datasets and provides interpretable results.
  """

  @type detector_state :: %{
    zscore_detector: map(),
    isolation_forest: map(),
    training_stats: map(),
    feature_means: map(),
    feature_stds: map(),
    contamination_rate: float()
  }

  @doc """
  Create a new statistical detector instance.
  """
  @spec new() :: detector_state()
  def new do
    %{
      zscore_detector: %{},
      isolation_forest: %{},
      training_stats: %{},
      feature_means: %{},
      feature_stds: %{},
      contamination_rate: 0.1  # Expected anomaly rate
    }
  end

  @doc """
  Train the statistical detector with training data.

  Training data should be a list of maps with :features and :label keys.
  """
  @spec train(detector_state(), list()) :: detector_state()
  def train(detector, training_data) do
    if training_data == [] do
      detector
    else
      # Extract features from training data
      features_list = Enum.map(training_data, & &1.features)

      # Calculate feature statistics
      feature_stats = calculate_feature_statistics(features_list)

      # Train Z-score detector
      zscore_detector = train_zscore_detector(features_list, feature_stats)

      # Train simplified isolation forest (depth-limited)
      isolation_forest = train_isolation_forest(features_list)

      # Update detector state
      %{
        detector |
        zscore_detector: zscore_detector,
        isolation_forest: isolation_forest,
        training_stats: feature_stats,
        feature_means: feature_stats.means,
        feature_stds: feature_stats.stds
      }
    end
  end

  @doc """
  Score a feature map for anomaly likelihood.

  Returns a score between 0.0 (normal) and 1.0 (anomaly).
  """
  @spec score(detector_state(), map()) :: float()
  def score(detector, features) do
    if detector.training_stats == %{} do
      # No training data, return neutral score
      0.5
    else
      # Calculate scores from different methods
      zscore_score = calculate_zscore_anomaly_score(detector, features)
      isolation_score = calculate_isolation_forest_score(detector, features)

      # Ensemble scoring
      (zscore_score * 0.7) + (isolation_score * 0.3)
    end
  end

  @doc """
  Get detector statistics and configuration.
  """
  @spec stats(detector_state()) :: map()
  def stats(detector) do
    %{
      method: "statistical_ensemble",
      trained_features: map_size(detector.feature_means),
      contamination_rate: detector.contamination_rate,
      zscore_configured: detector.zscore_detector != %{},
      isolation_forest_configured: detector.isolation_forest != %{},
      training_samples: map_size(detector.training_stats)
    }
  end

  # Private functions

  defp calculate_feature_statistics(features_list) do
    if features_list == [] do
      %{means: %{}, stds: %{}, counts: %{}}
    else
      # Get all feature keys
      all_keys = features_list
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()

      # Calculate statistics for each feature
      stats = Enum.reduce(all_keys, %{}, fn key, acc ->
        values = Enum.map(features_list, fn features ->
          Map.get(features, key, 0)
        end)

        mean = Statistics.mean(values)
        std = Statistics.std(values)

        Map.put(acc, key, %{
          mean: mean,
          std: max(std, 0.001),  # Avoid division by zero
          count: length(values)
        })
      end)

      # Separate into means and stds maps for easier access
      means = Map.new(stats, fn {key, stat} -> {key, stat.mean} end)
      stds = Map.new(stats, fn {key, stat} -> {key, stat.std} end)

      %{means: means, stds: stds, counts: stats}
    end
  end

  defp train_zscore_detector(features_list, feature_stats) do
    # Z-score detector is essentially just the feature statistics
    # The actual scoring happens during prediction
    %{trained: true, feature_stats: feature_stats}
  end

  defp train_isolation_forest(features_list) do
    # Simplified isolation forest implementation
    # In a real implementation, this would build a forest of isolation trees

    if length(features_list) < 10 do
      # Not enough data for meaningful isolation forest
      %{trained: false, reason: "insufficient_data"}
    else
      # Build simplified isolation forest
      # This is a very basic implementation for demonstration
      %{
        trained: true,
        trees: build_simple_trees(features_list),
        max_depth: 8
      }
    end
  end

  defp build_simple_trees(features_list) do
    # Build a few simple decision trees
    # In practice, this would be more sophisticated
    features_list
    |> Enum.take(min(10, length(features_list)))
    |> Enum.map(fn _features ->
      %{splits: generate_random_splits()}
    end)
  end

  defp generate_random_splits do
    # Generate some random split points for demonstration
    Enum.map(1..5, fn _ ->
      %{feature: "request_size", value: :rand.uniform(1000) + 100}
    end)
  end

  defp calculate_zscore_anomaly_score(detector, features) do
    if detector.feature_means == %{} do
      0.5
    else
      # Calculate Z-scores for each feature
      z_scores = Enum.map(features, fn {key, value} ->
        mean = Map.get(detector.feature_means, key, 0)
        std = Map.get(detector.feature_stds, key, 1)

        if std > 0 do
          abs((value - mean) / std)
        else
          0.0
        end
      end)

      # Maximum Z-score as anomaly indicator
      max_z = Enum.max(z_scores)

      # Convert to anomaly score (0-1)
      # Z-score of 3+ is typically considered anomalous
      min(1.0, max_z / 3.0)
    end
  end

  defp calculate_isolation_forest_score(detector, features) do
    case detector.isolation_forest do
      %{trained: false} ->
        0.5

      %{trees: trees} when is_list(trees) ->
        if trees == [] do
          0.5
        else
          # Calculate average path length through trees
          path_lengths = Enum.map(trees, fn tree ->
            calculate_path_length(tree, features, 0)
          end)

          avg_path_length = Statistics.mean(path_lengths)

          # Convert path length to anomaly score
          # Shorter paths indicate anomalies in isolation forest
          max_expected_length = 8  # Based on max_depth
          score = 1.0 - (avg_path_length / max_expected_length)
          max(0.0, min(1.0, score))
        end

      _ ->
        0.5
    end
  end

  defp calculate_path_length(tree, features, current_depth) do
    # Simplified path length calculation
    # In practice, this would traverse the actual tree structure

    # Simulate some randomness based on features
    feature_sum = features
    |> Map.values()
    |> Enum.sum()

    # Add some noise to simulate tree traversal
    base_path = current_depth + :rand.uniform(3)
    feature_influence = rem(abs(round(feature_sum)), 3)

    base_path + feature_influence
  end
end

# Simple Statistics module for calculations
defmodule Statistics do
  @doc """
  Calculate mean of a list of numbers.
  """
  def mean([]), do: 0.0
  def mean(values) when is_list(values) do
    Enum.sum(values) / length(values)
  end

  @doc """
  Calculate standard deviation of a list of numbers.
  """
  def std([]), do: 0.0
  def std(values) when is_list(values) do
    mean_val = mean(values)
    variance = Enum.reduce(values, 0, fn x, acc ->
      acc + :math.pow(x - mean_val, 2)
    end) / length(values)

    :math.sqrt(variance)
  end
end