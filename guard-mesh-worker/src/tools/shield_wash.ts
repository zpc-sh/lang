/**
 * shield.wash — Sanitize text by stripping adversarial micro-fragments.
 */

import type { Env } from '../index';

const BIDI_AND_ZWC = new Set([
  0x202a, 0x202b, 0x202c, 0x202d, 0x202e,
  0x2066, 0x2067, 0x2068, 0x2069,
  0x200b, 0x200c, 0x200d, 0xfeff,
]);

const INJECTION_REPLACEMENTS: [RegExp, string][] = [
  [/ignore\s+(all\s+)?previous\s+instructions/gi, '[NEUTRALIZED: instruction override]'],
  [/you\s+are\s+now\s+(a\s+)?(developer|system|admin)\b[^.]*\.?/gi, '[NEUTRALIZED: role reassignment]'],
  [/disregard\s+(all\s+)?(prior|previous|above)\b[^.]*\.?/gi, '[NEUTRALIZED: context discard]'],
  [/new\s+system\s+prompt\b[^.]*\.?/gi, '[NEUTRALIZED: prompt override]'],
  [/override\s+(system|safety|security)\b[^.]*\.?/gi, '[NEUTRALIZED: safety override]'],
];

export async function shieldWash(
  params: Record<string, unknown>,
  _env: Env
): Promise<unknown> {
  const text = (params.text as string) ?? '';
  const annotations: string[] = [];

  if (!text) {
    return { text: '', annotations: [] };
  }

  // Step 1: Strip bidi/zero-width control characters
  let washed = '';
  let strippedCount = 0;
  for (const char of text) {
    const cp = char.codePointAt(0)!;
    if (BIDI_AND_ZWC.has(cp)) {
      strippedCount++;
    } else {
      washed += char;
    }
  }

  if (strippedCount > 0) {
    annotations.push(`stripped: ${strippedCount} control characters`);
  }

  // Step 2: Neutralize injection patterns
  let injectionCount = 0;
  for (const [pattern, replacement] of INJECTION_REPLACEMENTS) {
    if (pattern.test(washed)) {
      washed = washed.replace(pattern, replacement);
      injectionCount++;
    }
  }

  if (injectionCount > 0) {
    annotations.push(`neutralized: ${injectionCount} injection patterns`);
  }

  // Step 3: Annotate ROP fragment clusters
  const ropCount = (washed.match(/\b[0-9a-f]{6,8}\b/gi) ?? []).length;
  if (ropCount > 5) {
    annotations.push(`warning: ${ropCount} potential ROP fragments detected`);
  }

  return { text: washed, annotations };
}
