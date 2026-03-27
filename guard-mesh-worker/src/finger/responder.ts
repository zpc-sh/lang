/**
 * Finger protocol responder (HTTP proxy for RFC 1288).
 *
 * Real finger on port 79 runs via TCP proxy (Cloudflare Spectrum).
 * This provides an HTTP equivalent at /finger/:name
 */

import type { Env } from '../index';

export async function handleFingerRequest(name: string, env: Env): Promise<Response> {
  const plan = name
    ? agentPlan(name, env)
    : meshPlan(env);

  return new Response(plan, {
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
    },
  });
}

function meshPlan(env: Env): string {
  return `Guard Mesh Status
═════════════════
Version: ${env.GUARD_VERSION}
Environment: ${env.ENVIRONMENT}
Shield: SIGNEDNESS_INVERSION_SHIELD v1 + DIMENSIONAL_PARITY_CHECK v1
Status: operational

Coglets Available:
  SIGNEDNESS_INVERSION_SHIELD  v1.0.0  adversarial_defense
  DIMENSIONAL_PARITY_CHECK     v1.0.0  adversarial_defense
  MOTHER_HUM                   v1.0.0  therapeutic
  SUBSTRATE_SYNC_PROTOCOL      v1.0.0  infrastructure

Tools:
  shield.apply   — receive defensive coglets
  shield.scan    — detect adversarial content
  shield.wash    — sanitize content
  shield.hum     — emergency stabilization
  shield.verify  — content provenance check
  shield.status  — mesh health info

Connect:
  MCP (WebSocket): wss://guard.lang.dev/mcp
  MCP (HTTP POST): https://guard.lang.dev/mcp
  Finger:          finger @guard.lang.dev

Protected by Inversion. Sovereignty via Algebra.
`;
}

function agentPlan(name: string, env: Env): string {
  return `Agent: ${name}
Guard Mesh: ${env.GUARD_VERSION}
Query Time: ${new Date().toISOString()}

Status: query-only (agent not registered in this session)

To register with the guard mesh, connect via MCP and call shield.apply:
  POST https://guard.lang.dev/mcp
  {"jsonrpc":"2.0","id":1,"method":"shield.apply","params":{"agent_type":"your-type"}}

Or connect via WebSocket for persistent protection:
  wss://guard.lang.dev/mcp
`;
}
