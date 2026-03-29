defmodule LangWeb.TextAnalysisLive do
  @moduledoc """
  LiveView for real-time text analysis and intelligence.

  Provides interactive text analysis with real-time feedback, including:
  - Text quality scoring
  - Readability analysis
  - Language detection
  - Sentiment analysis
  - Writing style insights
  - Real-time suggestions
  """

  use LangWeb, :live_view

  # Analysis state
  @default_analysis %{
    quality_score: nil,
    readability: nil,
    language: nil,
    sentiment: nil,
    word_count: 0,
    character_count: 0,
    paragraph_count: 0,
    sentence_count: 0,
    reading_time_minutes: 0,
    suggestions: [],
    processing: false,
    last_analyzed_at: nil
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:content, "")
      |> assign(:analysis, @default_analysis)
      |> assign(:analysis_enabled, true)
      |> assign(:auto_analyze, true)
      |> assign(:debounce_timer, nil)
      |> assign(:analysis_history, [])
      |> assign(:selected_format, "text")
      |> assign(:available_formats, [
        {"Plain Text", "text"},
        {"Markdown", "markdown"},
        {"JSON", "json"},
        {"JavaScript", "javascript"},
        {"Python", "python"},
        {"Elixir", "elixir"}
      ])

    {:ok, socket}
  end

  @impl true
  def handle_event("content_changed", %{"content" => content}, socket) do
    # Cancel existing timer
    if socket.assigns.debounce_timer do
      Process.cancel_timer(socket.assigns.debounce_timer)
    end

    # Basic stats we can calculate immediately
    basic_stats = calculate_basic_stats(content)

    socket =
      socket
      |> assign(:content, content)
      |> update(:analysis, &Map.merge(&1, basic_stats))

    # Set up debounced analysis if auto-analyze is enabled
    socket =
      if socket.assigns.auto_analyze and String.length(content) > 10 do
        timer = Process.send_after(self(), :analyze_content, 1000)
        assign(socket, :debounce_timer, timer)
      else
        assign(socket, :debounce_timer, nil)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("analyze_now", _params, socket) do
    send(self(), :analyze_content)
    {:noreply, put_analysis_processing(socket, true)}
  end

  @impl true
  def handle_event("toggle_auto_analyze", %{"auto_analyze" => auto_analyze}, socket) do
    auto_analyze = auto_analyze == "true"
    socket = assign(socket, :auto_analyze, auto_analyze)

    # If we just enabled auto-analyze and have content, analyze it
    socket =
      if auto_analyze and String.length(socket.assigns.content) > 10 do
        send(self(), :analyze_content)
        put_analysis_processing(socket, true)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("format_changed", %{"format" => format}, socket) do
    socket = assign(socket, :selected_format, format)

    # Re-analyze with new format if we have content
    socket =
      if String.length(socket.assigns.content) > 10 do
        send(self(), :analyze_content)
        put_analysis_processing(socket, true)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_content", _params, socket) do
    socket =
      socket
      |> assign(:content, "")
      |> assign(:analysis, @default_analysis)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:analyze_content, socket) do
    if String.length(socket.assigns.content) > 0 do
      perform_analysis(socket)
    else
      {:noreply, put_analysis_processing(socket, false)}
    end
  end

  # Private functions

  defp perform_analysis(socket) do
    content = socket.assigns.content
    format = socket.assigns.selected_format

    # For now, we'll create a mock analysis since the NIFs are broken
    # In a real implementation, this would call Lang.Native.analyze_text/2
    analysis = create_mock_analysis(content, format)

    # Add to history
    history_entry = %{
      timestamp: DateTime.utc_now(),
      content_preview:
        String.slice(content, 0, 100) <> if(String.length(content) > 100, do: "...", else: ""),
      analysis: analysis
    }

    socket =
      socket
      |> assign(:analysis, analysis)
      # Keep last 10
      |> update(:analysis_history, &[history_entry | Enum.take(&1, 9)])
      |> put_analysis_processing(false)

    {:noreply, socket}
  end

  defp create_mock_analysis(content, format) do
    basic_stats = calculate_basic_stats(content)

    # Mock advanced analysis
    quality_score = calculate_mock_quality_score(content)
    readability = calculate_mock_readability(content)
    language = detect_mock_language(content)
    sentiment = analyze_mock_sentiment(content)
    suggestions = generate_mock_suggestions(content, format)

    Map.merge(basic_stats, %{
      quality_score: quality_score,
      readability: readability,
      language: language,
      sentiment: sentiment,
      suggestions: suggestions,
      processing: false,
      last_analyzed_at: DateTime.utc_now()
    })
  end

  defp calculate_basic_stats(content) do
    word_count = content |> String.split() |> Enum.reject(&(&1 == "")) |> length()
    character_count = String.length(content)
    paragraph_count = content |> String.split("\n\n") |> Enum.reject(&(&1 == "")) |> length()
    sentence_count = content |> String.split(~r/[.!?]+/) |> Enum.reject(&(&1 == "")) |> length()
    # 200 WPM average
    reading_time = max(1, round(word_count / 200))

    %{
      word_count: word_count,
      character_count: character_count,
      paragraph_count: paragraph_count,
      sentence_count: sentence_count,
      reading_time_minutes: reading_time
    }
  end

  defp calculate_mock_quality_score(content) do
    # Mock quality scoring based on basic heuristics
    base_score = 70

    # Adjust for length
    length_bonus = min(20, String.length(content) / 100)

    # Adjust for variety (unique words vs total words)
    words = String.split(content)
    unique_words = words |> Enum.uniq() |> length()
    variety_bonus = if length(words) > 0, do: unique_words / length(words) * 10, else: 0

    # Adjust for sentence variety
    sentences = String.split(content, ~r/[.!?]+/)
    avg_sentence_length = if length(sentences) > 0, do: length(words) / length(sentences), else: 0
    sentence_bonus = if avg_sentence_length > 10 and avg_sentence_length < 25, do: 5, else: 0

    round(base_score + length_bonus + variety_bonus + sentence_bonus)
  end

  defp calculate_mock_readability(content) do
    # Mock readability using simplified Flesch Reading Ease
    words = String.split(content)
    sentences = String.split(content, ~r/[.!?]+/) |> Enum.reject(&(&1 == ""))

    if length(words) > 0 and length(sentences) > 0 do
      avg_sentence_length = length(words) / length(sentences)

      # Simple syllable estimation (vowel groups)
      syllables =
        words
        |> Enum.map(&count_syllables/1)
        |> Enum.sum()

      avg_syllables = if length(words) > 0, do: syllables / length(words), else: 0

      # Simplified Flesch score
      score = 206.835 - 1.015 * avg_sentence_length - 84.6 * avg_syllables
      score = max(0, min(100, score))

      cond do
        score >= 90 -> %{score: round(score), level: "Very Easy", color: "green"}
        score >= 80 -> %{score: round(score), level: "Easy", color: "green"}
        score >= 70 -> %{score: round(score), level: "Fairly Easy", color: "yellow"}
        score >= 60 -> %{score: round(score), level: "Standard", color: "yellow"}
        score >= 50 -> %{score: round(score), level: "Fairly Difficult", color: "orange"}
        score >= 30 -> %{score: round(score), level: "Difficult", color: "red"}
        true -> %{score: round(score), level: "Very Difficult", color: "red"}
      end
    else
      %{score: 0, level: "Unknown", color: "gray"}
    end
  end

  defp count_syllables(word) do
    # Very simple syllable counting - count vowel groups
    vowels = ~r/[aeiouy]+/i
    matches = Regex.scan(vowels, word)
    max(1, length(matches))
  end

  defp detect_mock_language(content) do
    # Mock language detection based on simple patterns
    cond do
      Regex.match?(~r/\b(the|and|or|but|in|on|at|to|for|of|with|by)\b/i, content) ->
        %{language: "English", confidence: 0.85}

      Regex.match?(~r/\b(el|la|de|en|y|o|pero|con|por|para)\b/i, content) ->
        %{language: "Spanish", confidence: 0.75}

      Regex.match?(~r/\b(le|la|de|et|ou|mais|dans|sur|avec|par)\b/i, content) ->
        %{language: "French", confidence: 0.70}

      true ->
        %{language: "Unknown", confidence: 0.50}
    end
  end

  defp analyze_mock_sentiment(content) do
    # Mock sentiment analysis based on simple word matching
    positive_words =
      ~w(good great excellent amazing wonderful fantastic happy love like enjoy best)

    negative_words = ~w(bad terrible awful horrible hate dislike worst problem issue error)

    words = content |> String.downcase() |> String.split()

    positive_count = Enum.count(words, &(&1 in positive_words))
    negative_count = Enum.count(words, &(&1 in negative_words))

    total_sentiment_words = positive_count + negative_count

    if total_sentiment_words > 0 do
      sentiment_score = (positive_count - negative_count) / total_sentiment_words

      cond do
        sentiment_score > 0.3 -> %{sentiment: "Positive", score: sentiment_score, color: "green"}
        sentiment_score < -0.3 -> %{sentiment: "Negative", score: sentiment_score, color: "red"}
        true -> %{sentiment: "Neutral", score: sentiment_score, color: "gray"}
      end
    else
      %{sentiment: "Neutral", score: 0, color: "gray"}
    end
  end

  defp generate_mock_suggestions(content, format) do
    suggestions = []

    # Length suggestions
    suggestions =
      if String.length(content) < 50 do
        [
          %{type: "improvement", text: "Consider expanding your content for better analysis"}
          | suggestions
        ]
      else
        suggestions
      end

    # Format-specific suggestions
    suggestions =
      case format do
        "markdown" ->
          if not String.contains?(content, "#") do
            [
              %{type: "formatting", text: "Consider adding headers with # for better structure"}
              | suggestions
            ]
          else
            suggestions
          end

        "json" ->
          if not String.contains?(content, "{") do
            [%{type: "error", text: "This doesn't appear to be valid JSON"} | suggestions]
          else
            suggestions
          end

        _ ->
          suggestions
      end

    # Readability suggestions
    sentences = String.split(content, ~r/[.!?]+/) |> Enum.reject(&(&1 == ""))

    avg_sentence_length =
      if length(sentences) > 0 do
        words = String.split(content)
        length(words) / length(sentences)
      else
        0
      end

    suggestions =
      if avg_sentence_length > 30 do
        [
          %{
            type: "improvement",
            text: "Consider breaking up long sentences for better readability"
          }
          | suggestions
        ]
      else
        suggestions
      end

    # Limit to 5 suggestions
    Enum.take(suggestions, 5)
  end

  defp put_analysis_processing(socket, processing) do
    update(socket, :analysis, &Map.put(&1, :processing, processing))
  end
end
