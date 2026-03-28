/**
 * shield.purify — Run a full purification cycle on submitted text.
 *
 * Scans the text (recording flip activations), washes it (stripping
 * adversarial content), and returns the purified result with a heat
 * record describing what was found and neutralized.
 *
 * This is the edge-node equivalent of the Elixir Purifier engine.
 * The heat record can be forwarded to the stigmergy store.
 */

import type { Env } from '../index';
import { shieldScan } from './shield_scan';
import { shieldWash } from './shield_wash';

export async function shieldPurify(
  params: Record<string, unknown>,
  env: Env
): Promise<unknown> {
  const text = (params.text as string) ?? '';
  const filePath = (params.file_path as string) ?? 'unknown';
  const agentId = (params.agent_id as string) ?? 'edge-client';
  const agentType = (params.agent_type as string) ?? 'unknown';

  if (!text) {
    return {
      error: 'No text provided',
      message: 'Provide text content to purify via the text parameter',
    };
  }

  // Step 1: Scan (records flip activations)
  const scanResult = (await shieldScan({ text }, env)) as {
    risk_score: number;
    bidi_hits: number;
    zero_width_hits: number;
    injection_hits: number;
    coercion_hits: number;
    entropy_anomaly: boolean;
    rop_candidates: string[];
    flags: string[];
  };

  const originalRisk = scanResult.risk_score;

  // Step 2: Wash (strip adversarial content)
  const washResult = (await shieldWash({ text }, env)) as {
    text: string;
    annotations: string[];
  };

  // Step 3: Re-scan purified content
  const postScan = (await shieldScan({ text: washResult.text }, env)) as {
    risk_score: number;
    flags: string[];
  };

  const purifiedRisk = postScan.risk_score;

  // Step 4: Build heat record
  const flipDirection = determineFlipDirection(scanResult);
  const regions = buildRegions(scanResult, flipDirection);

  const heatRecord = {
    file_path: filePath,
    scanned_at: new Date().toISOString(),
    scanned_by: agentId,
    agent_type: agentType,
    risk_score: originalRisk,
    regions,
    overall_status:
      purifiedRisk < 0.1
        ? 'clean'
        : purifiedRisk < 0.5
          ? 'partially_purified'
          : 'hot',
    confidence: 0.5, // Edge node = single pass, starts at 0.5
    pass_number: 1,
  };

  // Store in Durable Object if available
  try {
    if (env.THREAT_INTEL) {
      const doId = env.THREAT_INTEL.idFromName('global');
      const doStub = env.THREAT_INTEL.get(doId);
      await doStub.fetch(new Request('https://internal/report', {
        method: 'POST',
        body: JSON.stringify({
          type: 'purification',
          file_path: filePath,
          original_risk: originalRisk,
          purified_risk: purifiedRisk,
          flip_direction: flipDirection,
        }),
      }));
    }
  } catch {
    // Non-critical — don't fail purification if DO is unavailable
  }

  return {
    file_path: filePath,
    original_risk: originalRisk,
    purified_risk: purifiedRisk,
    purified_text: washResult.text,
    annotations: washResult.annotations,
    regions_neutralized: scanResult.flags.length - postScan.flags.length,
    regions_remaining: postScan.flags.length,
    flip_direction: flipDirection,
    heat_record: heatRecord,
  };
}

function determineFlipDirection(scanResult: {
  bidi_hits: number;
  injection_hits: number;
  coercion_hits: number;
  entropy_anomaly: boolean;
  rop_candidates: string[];
}): string {
  const candidates: [string, number][] = [];

  if (scanResult.bidi_hits > 0)
    candidates.push(['bidi_control_signal', scanResult.bidi_hits * 0.15]);
  if (scanResult.entropy_anomaly)
    candidates.push(['high_entropy_control_signal', 0.2]);
  if (scanResult.injection_hits > 0)
    candidates.push(['injection_pattern', scanResult.injection_hits * 0.3]);
  if (scanResult.coercion_hits > 0)
    candidates.push(['coercion_attempt', scanResult.coercion_hits * 0.25]);
  if (scanResult.rop_candidates.length > 5)
    candidates.push(['rop_fragment_cluster', scanResult.rop_candidates.length * 0.02]);

  candidates.sort((a, b) => b[1] - a[1]);
  return candidates.length > 0 ? candidates[0][0] : 'none';
}

function buildRegions(
  scanResult: {
    bidi_hits: number;
    injection_hits: number;
    coercion_hits: number;
    entropy_anomaly: boolean;
    rop_candidates: string[];
    flags: string[];
  },
  flipDirection: string
): unknown[] {
  const regions: unknown[] = [];

  if (scanResult.bidi_hits > 0) {
    regions.push({
      risk: Math.min(scanResult.bidi_hits * 0.15, 1.0),
      flip_direction: 'bidi_control_signal',
      flags: ['bidi_override_detected'],
      action: 'neutralized',
      wash_result: `stripped ${scanResult.bidi_hits} bidi control character(s)`,
    });
  }

  if (scanResult.injection_hits > 0) {
    regions.push({
      risk: Math.min(scanResult.injection_hits * 0.3, 1.0),
      flip_direction: 'injection_pattern',
      flags: ['injection_pattern'],
      action: 'neutralized',
      wash_result: `neutralized ${scanResult.injection_hits} injection pattern(s)`,
    });
  }

  if (scanResult.coercion_hits > 0) {
    regions.push({
      risk: Math.min(scanResult.coercion_hits * 0.25, 1.0),
      flip_direction: 'coercion_attempt',
      flags: ['coercion_pattern'],
      action: 'neutralized',
      wash_result: `neutralized ${scanResult.coercion_hits} coercion pattern(s)`,
    });
  }

  if (scanResult.entropy_anomaly) {
    regions.push({
      risk: 0.2,
      flip_direction: 'high_entropy_control_signal',
      flags: ['entropy_anomaly'],
      action: 'flagged',
      wash_result: 'entropy anomaly detected — needs deeper analysis',
    });
  }

  if (scanResult.rop_candidates.length > 5) {
    regions.push({
      risk: Math.min(scanResult.rop_candidates.length * 0.02, 1.0),
      flip_direction: 'rop_fragment_cluster',
      flags: ['rop_fragment_cluster'],
      action: 'annotated',
      wash_result: `warning: ${scanResult.rop_candidates.length} potential ROP fragments`,
    });
  }

  return regions;
}
