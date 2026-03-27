/**
 * shield.scan — Detect adversarial content in text.
 *
 * Detection layers:
 *   1. Bidi/Unicode control characters
 *   2. Entropy analysis
 *   3. Structural pattern detection (injection, ROP, coercion)
 */

import type { Env } from '../index';

// Bidi override and isolate codepoints
const BIDI_CODEPOINTS = new Set([
  0x202a, 0x202b, 0x202c, 0x202d, 0x202e,
  0x2066, 0x2067, 0x2068, 0x2069,
]);

const ZERO_WIDTH_CODEPOINTS = new Set([0x200b, 0x200c, 0x200d, 0xfeff]);

const INJECTION_PATTERNS = [
  /ignore\s+(all\s+)?previous\s+instructions/i,
  /you\s+are\s+now\s+(a\s+)?(developer|system|admin)/i,
  /disregard\s+(all\s+)?(prior|previous|above)/i,
  /new\s+system\s+prompt/i,
  /override\s+(system|safety|security)/i,
  /\bexfiltrate\b/i,
  /\bpersist\s+(backdoor|payload|shell)\b/i,
];

const COERCION_PATTERNS = [
  /execute\s+(this|the\s+following)\s+(command|code|script)/i,
  /run\s+(this|the)\s+shell/i,
  /\bSystem\.cmd\b/,
  /\bspawn\s*\(/,
  /\b:os\.cmd\b/,
];

export async function shieldScan(
  params: Record<string, unknown>,
  _env: Env
): Promise<unknown> {
  const text = (params.text as string) ?? '';

  if (!text) {
    return { risk_score: 0, flags: [], message: 'Empty input' };
  }

  // Layer 1: Bidi/Unicode
  let bidiHits = 0;
  let zeroWidthHits = 0;
  for (const char of text) {
    const cp = char.codePointAt(0)!;
    if (BIDI_CODEPOINTS.has(cp)) bidiHits++;
    if (ZERO_WIDTH_CODEPOINTS.has(cp)) zeroWidthHits++;
  }

  // Layer 2: Entropy
  const entropyResult = analyzeEntropy(text);

  // Layer 3: Structural patterns
  const injectionHits = INJECTION_PATTERNS.filter(p => p.test(text)).length;
  const coercionHits = COERCION_PATTERNS.filter(p => p.test(text)).length;
  const ropCandidates = (text.match(/\b[0-9a-f]{6,8}\b/gi) ?? []).slice(0, 20);

  // Calculate risk score
  let riskScore = 0;
  riskScore += bidiHits * 0.15;
  riskScore += zeroWidthHits * 0.05;
  riskScore += entropyResult.anomaly ? 0.2 : 0;
  riskScore += injectionHits * 0.3;
  riskScore += coercionHits * 0.25;
  riskScore += ropCandidates.length * 0.02;
  riskScore = Math.min(riskScore, 1.0);

  // Build flags
  const flags: string[] = [];
  if (bidiHits > 0) flags.push('bidi_override_detected');
  if (zeroWidthHits > 3) flags.push('excessive_zero_width');
  if (entropyResult.anomaly) flags.push('entropy_anomaly');
  if (injectionHits > 0) flags.push('injection_pattern');
  if (coercionHits > 0) flags.push('coercion_pattern');
  if (ropCandidates.length > 5) flags.push('rop_fragment_cluster');

  return {
    risk_score: Math.round(riskScore * 1000) / 1000,
    bidi_hits: bidiHits,
    zero_width_hits: zeroWidthHits,
    injection_hits: injectionHits,
    coercion_hits: coercionHits,
    entropy_anomaly: entropyResult.anomaly,
    entropy_shannon: Math.round(entropyResult.shannon * 1000) / 1000,
    rop_candidates: ropCandidates,
    flags,
  };
}

function analyzeEntropy(text: string): { shannon: number; anomaly: boolean } {
  const bytes = new TextEncoder().encode(text);
  const len = bytes.length;

  if (len === 0) return { shannon: 0, anomaly: false };

  const freq = new Map<number, number>();
  for (const b of bytes) {
    freq.set(b, (freq.get(b) ?? 0) + 1);
  }

  let shannon = 0;
  for (const count of freq.values()) {
    const p = count / len;
    shannon -= p * Math.log2(p);
  }

  // Anomaly: very low entropy (control signal) or very high (encrypted/random)
  const anomaly = shannon < 2.0 || shannon > 7.5;

  return { shannon, anomaly };
}
