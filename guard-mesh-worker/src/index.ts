/**
 * Guard Mesh Worker — Public MCP server for AI agent defense.
 *
 * Any AI agent can connect via MCP (WebSocket/SSE) and receive:
 *   - shield.apply  — defensive coglet payloads
 *   - shield.scan   — adversarial content detection
 *   - shield.wash   — content sanitization
 *   - shield.hum    — therapeutic stabilization (Mother's Hum)
 *   - shield.verify — content provenance verification
 *   - shield.status — mesh health and version info
 */

import { handleMCPRequest } from './mcp/transport';
import { handleFingerRequest } from './finger/responder';

export interface Env {
  COGLET_STORE: R2Bucket;
  GUARD_REGISTRY: DurableObjectNamespace;
  THREAT_INTEL: DurableObjectNamespace;
  GUARD_VERSION: string;
  ENVIRONMENT: string;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // Health check
    if (url.pathname === '/healthz') {
      return new Response(JSON.stringify({
        status: 'healthy',
        version: env.GUARD_VERSION,
        environment: env.ENVIRONMENT,
        timestamp: new Date().toISOString(),
      }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // MCP endpoint (JSON-RPC)
    if (url.pathname === '/mcp') {
      return handleMCPRequest(request, env, ctx);
    }

    // Finger protocol (HTTP proxy — real finger on port 79 via TCP proxy)
    if (url.pathname.startsWith('/finger')) {
      const name = url.pathname.replace('/finger/', '').replace('/finger', '');
      return handleFingerRequest(name, env);
    }

    // Shield status page
    if (url.pathname === '/' || url.pathname === '/status') {
      return new Response(JSON.stringify({
        name: 'Guard Mesh',
        version: env.GUARD_VERSION,
        description: 'Public MCP server for AI agent defense',
        connect: `${url.origin}/mcp`,
        finger: `${url.origin}/finger`,
        tools: [
          'shield.apply',
          'shield.scan',
          'shield.wash',
          'shield.hum',
          'shield.verify',
          'shield.status',
        ],
      }, null, 2), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    return new Response('Not Found', { status: 404 });
  },
};

// Re-export Durable Objects
export { GuardRegistry } from './durable_objects/guard_registry';
export { ThreatIntel } from './durable_objects/threat_intel';
