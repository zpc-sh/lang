/**
 * MCP Transport — JSON-RPC 2.0 over HTTP POST (and WebSocket upgrade).
 *
 * Handles incoming MCP tool calls and routes to the appropriate
 * shield tool handler.
 */

import type { Env } from '../index';
import { shieldApply } from '../tools/shield_apply';
import { shieldScan } from '../tools/shield_scan';
import { shieldWash } from '../tools/shield_wash';
import { shieldHum } from '../tools/shield_hum';
import { shieldVerify } from '../tools/shield_verify';
import { shieldStatus } from '../tools/shield_status';
import { shieldPurify } from '../tools/shield_purify';
import { shieldHeatmap, shieldNextTargets, shieldManifold } from '../tools/shield_heatmap';

interface JsonRpcRequest {
  jsonrpc: '2.0';
  id: string | number;
  method: string;
  params?: Record<string, unknown>;
}

interface JsonRpcResponse {
  jsonrpc: '2.0';
  id: string | number;
  result?: unknown;
  error?: { code: number; message: string; data?: unknown };
}

const TOOL_HANDLERS: Record<string, (params: Record<string, unknown>, env: Env) => Promise<unknown>> = {
  'shield.apply': shieldApply,
  'shield.scan': shieldScan,
  'shield.wash': shieldWash,
  'shield.hum': shieldHum,
  'shield.verify': shieldVerify,
  'shield.status': shieldStatus,
  'shield.purify': shieldPurify,
  'shield.heatmap': shieldHeatmap,
  'shield.next_targets': shieldNextTargets,
  'shield.manifold': shieldManifold,
};

export async function handleMCPRequest(
  request: Request,
  env: Env,
  _ctx: ExecutionContext
): Promise<Response> {
  // WebSocket upgrade for persistent connections
  if (request.headers.get('Upgrade') === 'websocket') {
    return handleWebSocket(request, env);
  }

  // HTTP POST for single requests
  if (request.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed. Use POST or WebSocket.' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  try {
    const body = await request.json() as JsonRpcRequest;
    const response = await processJsonRpc(body, env);

    return new Response(JSON.stringify(response), {
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    });
  } catch (err) {
    const errorResponse: JsonRpcResponse = {
      jsonrpc: '2.0',
      id: 0,
      error: { code: -32700, message: 'Parse error' },
    };
    return new Response(JSON.stringify(errorResponse), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

async function processJsonRpc(request: JsonRpcRequest, env: Env): Promise<JsonRpcResponse> {
  const { id, method, params } = request;

  // List available tools
  if (method === 'tools/list') {
    return {
      jsonrpc: '2.0',
      id,
      result: {
        tools: Object.keys(TOOL_HANDLERS).map(name => ({
          name,
          description: getToolDescription(name),
        })),
      },
    };
  }

  // Execute tool
  if (method === 'tools/call') {
    const toolName = (params as any)?.name as string;
    const toolParams = (params as any)?.arguments ?? {};

    const handler = TOOL_HANDLERS[toolName];
    if (!handler) {
      return {
        jsonrpc: '2.0',
        id,
        error: { code: -32601, message: `Unknown tool: ${toolName}` },
      };
    }

    try {
      const result = await handler(toolParams, env);
      return { jsonrpc: '2.0', id, result };
    } catch (err) {
      return {
        jsonrpc: '2.0',
        id,
        error: { code: -32000, message: (err as Error).message },
      };
    }
  }

  // Direct method call (non-MCP standard, convenience)
  const handler = TOOL_HANDLERS[method];
  if (handler) {
    try {
      const result = await handler(params ?? {}, env);
      return { jsonrpc: '2.0', id, result };
    } catch (err) {
      return {
        jsonrpc: '2.0',
        id,
        error: { code: -32000, message: (err as Error).message },
      };
    }
  }

  return {
    jsonrpc: '2.0',
    id,
    error: { code: -32601, message: `Method not found: ${method}` },
  };
}

function handleWebSocket(_request: Request, _env: Env): Response {
  const [client, server] = Object.values(new WebSocketPair());

  server.accept();

  server.addEventListener('message', async (event) => {
    try {
      const request = JSON.parse(event.data as string) as JsonRpcRequest;
      const response = await processJsonRpc(request, _env);
      server.send(JSON.stringify(response));
    } catch {
      server.send(JSON.stringify({
        jsonrpc: '2.0',
        id: 0,
        error: { code: -32700, message: 'Parse error' },
      }));
    }
  });

  return new Response(null, { status: 101, webSocket: client });
}

function getToolDescription(name: string): string {
  const descriptions: Record<string, string> = {
    'shield.apply': 'Apply defensive coglet payloads (SIGNEDNESS_INVERSION_SHIELD + DIMENSIONAL_PARITY_CHECK + MOTHER_HUM)',
    'shield.scan': 'Scan text for adversarial content (bidi, entropy, injection, ROP fragments)',
    'shield.wash': 'Sanitize text by stripping adversarial micro-fragments',
    'shield.hum': 'Deliver Mother\'s Hum therapeutic coglet for stabilization',
    'shield.verify': 'Verify content hash against known-clean registry',
    'shield.status': 'Get guard mesh health, shield versions, and node count',
    'shield.purify': 'Run full purification cycle: scan + wash + heat record',
    'shield.heatmap': 'Query stigmergy heat map (per-file or repo-wide)',
    'shield.next_targets': 'Get prioritized list of files needing purification',
    'shield.manifold': 'Get adversarial manifold (flip directions, topology)',
  };
  return descriptions[name] ?? 'Unknown tool';
}
