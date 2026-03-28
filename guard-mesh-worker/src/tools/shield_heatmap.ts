/**
 * shield.heatmap — Query the stigmergy heat map.
 *
 * Returns the current purification status across all tracked files
 * (or a specific file). This is the edge-node heat map — the full
 * distributed heat map aggregates across all mesh nodes.
 *
 * Also provides shield.next_targets (prioritized purification queue)
 * and shield.manifold (adversarial topology).
 */

import type { Env } from '../index';

interface HeatRecord {
  file_path: string;
  scanned_at: string;
  scanned_by: string;
  agent_type: string;
  risk_score: number;
  overall_status: string;
  flip_direction: string;
}

// In-memory heat store for edge node (reset on deploy)
// Real persistence uses Durable Objects
const edgeHeatStore: Map<string, HeatRecord[]> = new Map();

export function recordHeat(record: HeatRecord): void {
  const existing = edgeHeatStore.get(record.file_path) ?? [];
  existing.push(record);
  edgeHeatStore.set(record.file_path, existing);
}

export async function shieldHeatmap(
  params: Record<string, unknown>,
  env: Env
): Promise<unknown> {
  const filePath = params.file_path as string | undefined;

  // Try Durable Object first for persistence
  let doRecords: unknown = null;
  try {
    if (env.THREAT_INTEL) {
      const doId = env.THREAT_INTEL.idFromName('global');
      const doStub = env.THREAT_INTEL.get(doId);
      const response = await doStub.fetch(
        new Request('https://internal/summary', { method: 'GET' })
      );
      doRecords = await response.json();
    }
  } catch {
    // Fall back to in-memory store
  }

  if (filePath) {
    // Per-file heat history
    const records = edgeHeatStore.get(filePath) ?? [];
    return {
      file_path: filePath,
      records,
      passes: records.length,
      message: records.length === 0
        ? 'No purification records for this file on this edge node'
        : undefined,
    };
  }

  // Repo-wide summary
  const files: unknown[] = [];
  let hot = 0;
  let partial = 0;
  let clean = 0;

  for (const [path, records] of edgeHeatStore.entries()) {
    const latest = records[records.length - 1];
    const status = latest.overall_status;

    if (status === 'hot') hot++;
    else if (status === 'partially_purified') partial++;
    else clean++;

    files.push({
      path,
      status,
      risk: latest.risk_score,
      passes: records.length,
      last_scanned: latest.scanned_at,
    });
  }

  return {
    files,
    total: files.length,
    summary: { hot, partially_purified: partial, clean },
    do_available: doRecords !== null,
  };
}

export async function shieldNextTargets(
  params: Record<string, unknown>,
  _env: Env
): Promise<unknown> {
  const count = (params.count as number) ?? 10;

  // Sort by risk (highest first), filter to non-clean
  const targets: { path: string; risk: number; last_scanned: string; status: string }[] = [];

  for (const [path, records] of edgeHeatStore.entries()) {
    const latest = records[records.length - 1];
    if (latest.overall_status !== 'clean' && latest.overall_status !== 'verified') {
      targets.push({
        path,
        risk: latest.risk_score,
        last_scanned: latest.scanned_at,
        status: latest.overall_status,
      });
    }
  }

  targets.sort((a, b) => b.risk - a.risk);

  return {
    targets: targets.slice(0, count),
    total_hot: targets.length,
  };
}

export async function shieldManifold(
  params: Record<string, unknown>,
  _env: Env
): Promise<unknown> {
  const filePath = params.file_path as string | undefined;

  if (filePath) {
    const records = edgeHeatStore.get(filePath) ?? [];
    const flipDirections = records.map((r) => ({
      direction: r.flip_direction,
      risk: r.risk_score,
      pass: records.indexOf(r) + 1,
    }));

    return {
      file_path: filePath,
      passes: records.length,
      flip_directions: flipDirections,
      convergence: records.length > 0 ? 1.0 - Math.pow(0.5, records.length) : 0,
    };
  }

  // Aggregate manifold across all files
  const directionCounts: Map<string, { count: number; totalRisk: number }> = new Map();

  for (const records of edgeHeatStore.values()) {
    for (const record of records) {
      const existing = directionCounts.get(record.flip_direction) ?? {
        count: 0,
        totalRisk: 0,
      };
      existing.count++;
      existing.totalRisk += record.risk_score;
      directionCounts.set(record.flip_direction, existing);
    }
  }

  const topology = Array.from(directionCounts.entries())
    .map(([direction, data]) => ({
      direction,
      count: data.count,
      total_risk: Math.round(data.totalRisk * 1000) / 1000,
    }))
    .sort((a, b) => b.total_risk - a.total_risk);

  return {
    files_tracked: edgeHeatStore.size,
    topology,
  };
}
