/**
 * shield.verify — Verify content against known-clean registry.
 */

import type { Env } from '../index';

export async function shieldVerify(
  params: Record<string, unknown>,
  env: Env
): Promise<unknown> {
  const contentHash = (params.content_hash as string) ?? '';

  if (!contentHash) {
    return { clean: false, provenance: 'unknown', confidence: 0, error: 'No content_hash provided' };
  }

  // Check R2 known-clean registry
  try {
    const key = `known-clean/${contentHash}`;
    const obj = await env.COGLET_STORE.get(key);

    if (obj) {
      const metadata = obj.customMetadata ?? {};
      return {
        clean: true,
        provenance: metadata.source ?? 'verified',
        confidence: 1.0,
        hash: contentHash,
        verified_at: metadata.verified_at ?? 'unknown',
      };
    }
  } catch {
    // R2 lookup failed, continue with unknown
  }

  return {
    clean: false,
    provenance: 'unknown',
    confidence: 0,
    hash: contentHash,
    message: 'Hash not found in known-clean registry',
  };
}
