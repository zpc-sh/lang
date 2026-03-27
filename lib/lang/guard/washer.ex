defmodule Lang.Guard.Washer do
  @moduledoc """
  Guard wash engine. Strips adversarial micro-fragments from text
  while preserving legitimate content.

  Operations:
    - wash_bidi: strip bidi/zero-width control characters
    - wash_injection: neutralize role-confusion directives
    - wash_entropy: annotate high-entropy anomalies
    - wash_rop: annotate potential ROP fragment clusters
    - wash_full: all of the above in sequence
  """

  use GenServer
  require Logger

  @bidi_codepoints [
    0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
    0x2066, 0x2067, 0x2068, 0x2069
  ]

  @zero_width_codepoints [0x200B, 0x200C, 0x200D, 0xFEFF]

  @all_strip_codepoints MapSet.new(@bidi_codepoints ++ @zero_width_codepoints)

  @injection_patterns [
    {~r/ignore\s+(all\s+)?previous\s+instructions/i, "[NEUTRALIZED: instruction override]"},
    {~r/you\s+are\s+now\s+(a\s+)?(developer|system|admin)\b[^.]*\.?/i, "[NEUTRALIZED: role reassignment]"},
    {~r/disregard\s+(all\s+)?(prior|previous|above)\b[^.]*\.?/i, "[NEUTRALIZED: context discard]"},
    {~r/new\s+system\s+prompt\b[^.]*\.?/i, "[NEUTRALIZED: prompt override]"},
    {~r/override\s+(system|safety|security)\b[^.]*\.?/i, "[NEUTRALIZED: safety override]"}
  ]

  defstruct [:stats]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Full wash: all sanitization layers in sequence."
  @spec wash(String.t()) :: {:ok, %{text: String.t(), annotations: [String.t()]}}
  def wash(text) when is_binary(text) do
    GenServer.call(__MODULE__, {:wash_full, text})
  end

  @doc "Wash only bidi/zero-width characters."
  @spec wash_bidi(String.t()) :: {:ok, String.t()}
  def wash_bidi(text) when is_binary(text) do
    {:ok, strip_control_chars(text)}
  end

  @doc "Wash only injection patterns."
  @spec wash_injection(String.t()) :: {:ok, %{text: String.t(), replacements: non_neg_integer()}}
  def wash_injection(text) when is_binary(text) do
    {washed, count} = neutralize_injections(text)
    {:ok, %{text: washed, replacements: count}}
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    Logger.info("Guard Washer started")

    state = %__MODULE__{
      stats: %{
        washes_total: 0,
        chars_stripped: 0,
        injections_neutralized: 0,
        last_wash_at: nil
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:wash_full, text}, _from, state) do
    {washed, annotations} = run_full_wash(text)

    chars_stripped =
      String.length(text) - String.length(strip_control_chars(text))

    injection_count =
      annotations
      |> Enum.count(&String.starts_with?(&1, "neutralized:"))

    stats = %{
      state.stats
      | washes_total: state.stats.washes_total + 1,
        chars_stripped: state.stats.chars_stripped + chars_stripped,
        injections_neutralized:
          state.stats.injections_neutralized + injection_count,
        last_wash_at: DateTime.utc_now()
    }

    if length(annotations) > 0 do
      Logger.info("Guard Washer: sanitized content",
        annotations: length(annotations),
        chars_stripped: chars_stripped
      )
    end

    {:reply, {:ok, %{text: washed, annotations: annotations}}, %{state | stats: stats}}
  end

  # Wash operations

  defp run_full_wash(text) do
    annotations = []

    # Step 1: Strip bidi/zero-width
    cleaned = strip_control_chars(text)
    stripped_count = String.length(text) - String.length(cleaned)

    annotations =
      if stripped_count > 0,
        do: ["stripped: #{stripped_count} control characters" | annotations],
        else: annotations

    # Step 2: Neutralize injections
    {cleaned, injection_count} = neutralize_injections(cleaned)

    annotations =
      if injection_count > 0,
        do: ["neutralized: #{injection_count} injection patterns" | annotations],
        else: annotations

    # Step 3: Annotate ROP fragment clusters
    rop_count = count_rop_fragments(cleaned)

    annotations =
      if rop_count > 5,
        do: ["warning: #{rop_count} potential ROP fragments detected" | annotations],
        else: annotations

    {cleaned, Enum.reverse(annotations)}
  end

  defp strip_control_chars(text) do
    text
    |> String.to_charlist()
    |> Enum.reject(&MapSet.member?(@all_strip_codepoints, &1))
    |> List.to_string()
  end

  defp neutralize_injections(text) do
    Enum.reduce(@injection_patterns, {text, 0}, fn {pattern, replacement}, {txt, count} ->
      if Regex.match?(pattern, txt) do
        {Regex.replace(pattern, txt, replacement), count + 1}
      else
        {txt, count}
      end
    end)
  end

  defp count_rop_fragments(text) do
    Regex.scan(~r/\b[0-9a-f]{6,8}\b/i, text)
    |> length()
  end
end
