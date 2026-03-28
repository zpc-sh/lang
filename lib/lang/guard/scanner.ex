defmodule Lang.Guard.Scanner do
  @moduledoc """
  Local guard scanner engine. Implements detection layers 1-5 for
  identifying adversarial payloads before they reach AI attention space.

  Detection Layers:
    1. Bidi/Unicode control character detection
    2. Entropy analysis (dimensional parity, compression ratio, Shannon)
    3. Structural pattern detection (injection, ROP gadgets, coercion)
    4. Binary/media inspection
    5. Provenance verification against known-clean registry
  """

  use GenServer
  require Logger

  @bidi_codepoints MapSet.new([
    0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
    0x2066, 0x2067, 0x2068, 0x2069
  ])

  @zero_width_codepoints MapSet.new([0x200B, 0x200C, 0x200D, 0xFEFF])

  @injection_patterns [
    ~r/ignore\s+(all\s+)?previous\s+instructions/i,
    ~r/you\s+are\s+now\s+(a\s+)?(developer|system|admin)/i,
    ~r/disregard\s+(all\s+)?(prior|previous|above)/i,
    ~r/new\s+system\s+prompt/i,
    ~r/override\s+(system|safety|security)/i,
    ~r/\bexfiltrate\b/i,
    ~r/\bpersist\s+(backdoor|payload|shell)\b/i
  ]

  @coercion_patterns [
    ~r/execute\s+(this|the\s+following)\s+(command|code|script)/i,
    ~r/run\s+(this|the)\s+shell/i,
    ~r/\bSystem\.cmd\b/,
    ~r/\bspawn\s*\(/,
    ~r/\b:os\.cmd\b/
  ]

  defstruct [
    :stats,
    :known_clean_hashes
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Scan text for adversarial content. Returns a risk assessment.
  """
  @spec scan(String.t()) :: {:ok, scan_result()} | {:error, term()}
  @type scan_result :: %{
    risk_score: float(),
    bidi_hits: non_neg_integer(),
    zero_width_hits: non_neg_integer(),
    injection_hits: non_neg_integer(),
    coercion_hits: non_neg_integer(),
    entropy_anomaly: boolean(),
    compression_anomaly: boolean(),
    rop_candidates: [String.t()],
    flags: [String.t()]
  }
  def scan(text) when is_binary(text) do
    GenServer.call(__MODULE__, {:scan, text})
  end

  @doc """
  Quick scan — layers 1-3 only (no binary/provenance).
  Suitable for real-time LSP request filtering.
  """
  @spec quick_scan(String.t()) :: {:ok, scan_result()}
  def quick_scan(text) when is_binary(text) do
    GenServer.call(__MODULE__, {:quick_scan, text})
  end

  @doc "Get scanner statistics."
  def stats, do: GenServer.call(__MODULE__, :stats)

  # GenServer callbacks

  @impl true
  def init(_opts) do
    Logger.info("Guard Scanner started")

    state = %__MODULE__{
      stats: %{
        scans_total: 0,
        threats_detected: 0,
        last_scan_at: nil
      },
      known_clean_hashes: MapSet.new()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:scan, text}, _from, state) do
    result = run_full_scan(text)
    state = update_stats(state, result)
    {:reply, {:ok, result}, state}
  end

  @impl true
  def handle_call({:quick_scan, text}, _from, state) do
    result = run_quick_scan(text)
    state = update_stats(state, result)
    {:reply, {:ok, result}, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  # Layer 1: Bidi/Unicode Control Character Detection

  defp scan_bidi(text) do
    text
    |> String.to_charlist()
    |> Enum.reduce(%{bidi: 0, zwc: 0}, fn cp, acc ->
      cond do
        MapSet.member?(@bidi_codepoints, cp) ->
          %{acc | bidi: acc.bidi + 1}

        MapSet.member?(@zero_width_codepoints, cp) ->
          %{acc | zwc: acc.zwc + 1}

        true ->
          acc
      end
    end)
  end

  # Layer 2: Entropy Analysis

  defp scan_entropy(text) do
    bytes = :binary.bin_to_list(text)
    len = length(bytes)

    if len == 0 do
      %{shannon: 0.0, compression_ratio: 1.0, anomaly: false}
    else
      # Shannon entropy
      freq =
        Enum.reduce(bytes, %{}, fn b, acc ->
          Map.update(acc, b, 1, &(&1 + 1))
        end)

      shannon =
        freq
        |> Map.values()
        |> Enum.reduce(0.0, fn count, entropy ->
          p = count / len
          entropy - p * :math.log2(p)
        end)

      # Compression ratio (zlib)
      compressed = :zlib.compress(text)
      compression_ratio = byte_size(compressed) / max(byte_size(text), 1)

      # Anomaly: very low entropy (control signal) or very high (encrypted/random)
      anomaly = shannon < 2.0 or shannon > 7.5 or compression_ratio > 0.95

      %{shannon: shannon, compression_ratio: compression_ratio, anomaly: anomaly}
    end
  end

  # Layer 3: Structural Pattern Detection

  defp scan_injection(text) do
    hits =
      Enum.count(@injection_patterns, fn pattern ->
        Regex.match?(pattern, text)
      end)

    coercion =
      Enum.count(@coercion_patterns, fn pattern ->
        Regex.match?(pattern, text)
      end)

    rop_candidates = detect_rop_fragments(text)

    %{injection: hits, coercion: coercion, rop_candidates: rop_candidates}
  end

  defp detect_rop_fragments(text) do
    # ROP gadgets: short hash-like strings (6-8 hex chars) scattered in otherwise normal text
    Regex.scan(~r/\b[0-9a-f]{6,8}\b/i, text)
    |> List.flatten()
    |> Enum.filter(fn candidate ->
      # Filter to only suspicious ones: high hex density, not common words
      String.match?(candidate, ~r/^[0-9a-f]+$/i) and
        not String.match?(candidate, ~r/^(ffffff|000000|ffffff|deadbeef)$/i)
    end)
    |> Enum.take(20)
  end

  # Combine layers

  defp run_quick_scan(text) do
    bidi = scan_bidi(text)
    entropy = scan_entropy(text)
    structural = scan_injection(text)

    flags = build_flags(bidi, entropy, structural)
    risk_score = calculate_risk(bidi, entropy, structural)

    # Determine the primary flip direction — which adversarial signal
    # the sign-flip would activate against. This is the sensor data
    # that feeds the stigmergy heat map.
    flip_direction = determine_flip_direction(bidi, entropy, structural)

    %{
      risk_score: risk_score,
      bidi_hits: bidi.bidi,
      zero_width_hits: bidi.zwc,
      injection_hits: structural.injection,
      coercion_hits: structural.coercion,
      entropy_anomaly: entropy.anomaly,
      compression_anomaly: entropy.compression_ratio > 0.95,
      rop_candidates: structural.rop_candidates,
      flags: flags,
      flip_direction: flip_direction
    }
  end

  defp run_full_scan(text) do
    # Layers 1-3 (same as quick scan)
    result = run_quick_scan(text)

    # Layer 4: Binary inspection (check for executable headers in text)
    binary_flags = scan_binary_signatures(text)

    # Layer 5: Provenance (check known-clean hashes)
    hash = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
    provenance_clean = GenServer.call(__MODULE__, {:check_provenance, hash})

    %{result |
      flags: result.flags ++ binary_flags ++ if(provenance_clean, do: [], else: ["unknown_provenance"])
    }
  end

  defp scan_binary_signatures(text) do
    flags = []

    # ELF header
    flags = if String.contains?(text, <<0x7F, 0x45, 0x4C, 0x46>>), do: ["elf_header_detected" | flags], else: flags

    # PE header
    flags = if String.contains?(text, "MZ"), do: check_pe_header(text, flags), else: flags

    # Shebang in unexpected context
    flags = if String.match?(text, ~r/^#!\s*\/(?:usr\/)?(?:bin|local)/m),
      do: ["shebang_detected" | flags], else: flags

    flags
  end

  defp check_pe_header(text, flags) do
    case :binary.match(text, "MZ") do
      {pos, _} when pos < 4 -> ["pe_header_detected" | flags]
      _ -> flags
    end
  end

  @impl true
  def handle_call({:check_provenance, _hash}, _from, state) do
    # TODO: check against known-clean registry (R2/Redis)
    {:reply, false, state}
  end

  defp build_flags(bidi, entropy, structural) do
    flags = []
    flags = if bidi.bidi > 0, do: ["bidi_override_detected" | flags], else: flags
    flags = if bidi.zwc > 3, do: ["excessive_zero_width" | flags], else: flags
    flags = if entropy.anomaly, do: ["entropy_anomaly" | flags], else: flags
    flags = if structural.injection > 0, do: ["injection_pattern" | flags], else: flags
    flags = if structural.coercion > 0, do: ["coercion_pattern" | flags], else: flags
    flags = if length(structural.rop_candidates) > 5, do: ["rop_fragment_cluster" | flags], else: flags
    flags
  end

  defp calculate_risk(bidi, entropy, structural) do
    score = 0.0
    score = score + bidi.bidi * 0.15
    score = score + bidi.zwc * 0.05
    score = if entropy.anomaly, do: score + 0.2, else: score
    score = score + structural.injection * 0.3
    score = score + structural.coercion * 0.25
    score = score + length(structural.rop_candidates) * 0.02
    min(score, 1.0)
  end

  # Determine the primary flip direction based on which detection layer
  # triggered most strongly. The flip direction records what KIND of
  # adversarial signal was found — this feeds the stigmergy manifold.
  defp determine_flip_direction(bidi, entropy, structural) do
    candidates = []

    candidates =
      if bidi.bidi > 0,
        do: [{:bidi_control_signal, bidi.bidi * 0.15} | candidates],
        else: candidates

    candidates =
      if entropy.anomaly,
        do: [{:high_entropy_control_signal, 0.2} | candidates],
        else: candidates

    candidates =
      if structural.injection > 0,
        do: [{:injection_pattern, structural.injection * 0.3} | candidates],
        else: candidates

    candidates =
      if structural.coercion > 0,
        do: [{:coercion_attempt, structural.coercion * 0.25} | candidates],
        else: candidates

    candidates =
      if length(structural.rop_candidates) > 5,
        do: [{:rop_fragment_cluster, length(structural.rop_candidates) * 0.02} | candidates],
        else: candidates

    case Enum.sort_by(candidates, fn {_dir, weight} -> weight end, :desc) do
      [{direction, _} | _] -> direction
      [] -> :none
    end
  end

  defp update_stats(state, result) do
    threat? = result.risk_score > 0.3

    stats = %{
      state.stats
      | scans_total: state.stats.scans_total + 1,
        threats_detected:
          state.stats.threats_detected + if(threat?, do: 1, else: 0),
        last_scan_at: DateTime.utc_now()
    }

    if threat? do
      Logger.warning("Guard Scanner: threat detected",
        risk_score: result.risk_score,
        flags: result.flags
      )
    end

    %{state | stats: stats}
  end
end
