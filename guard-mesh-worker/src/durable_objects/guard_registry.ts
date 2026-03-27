/**
 * GuardRegistry Durable Object — tracks connected AI agents,
 * their shield versions, and wash history.
 */

interface AgentRecord {
  agent_id: string;
  agent_type: string;
  shield_version: string;
  connected_at: string;
  last_seen: string;
  washes: number;
  threats_blocked: number;
}

export class GuardRegistry {
  private state: DurableObjectState;
  private agents: Map<string, AgentRecord> = new Map();

  constructor(state: DurableObjectState, _env: unknown) {
    this.state = state;

    // Restore state
    this.state.blockConcurrencyWhile(async () => {
      const stored = await this.state.storage.get<Map<string, AgentRecord>>('agents');
      if (stored) this.agents = stored;
    });
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/register' && request.method === 'POST') {
      const body = await request.json() as { agent_id: string; agent_type: string; shield_version: string };
      const record: AgentRecord = {
        agent_id: body.agent_id,
        agent_type: body.agent_type,
        shield_version: body.shield_version,
        connected_at: new Date().toISOString(),
        last_seen: new Date().toISOString(),
        washes: 0,
        threats_blocked: 0,
      };
      this.agents.set(body.agent_id, record);
      await this.state.storage.put('agents', this.agents);
      return new Response(JSON.stringify({ ok: true, agent_id: body.agent_id }));
    }

    if (url.pathname === '/heartbeat' && request.method === 'POST') {
      const body = await request.json() as { agent_id: string };
      const agent = this.agents.get(body.agent_id);
      if (agent) {
        agent.last_seen = new Date().toISOString();
        await this.state.storage.put('agents', this.agents);
      }
      return new Response(JSON.stringify({ ok: true }));
    }

    if (url.pathname === '/stats') {
      const now = Date.now();
      const active = [...this.agents.values()].filter(
        a => now - new Date(a.last_seen).getTime() < 3600_000
      );
      return new Response(JSON.stringify({
        total_registered: this.agents.size,
        active_last_hour: active.length,
        agents: active.map(a => ({
          agent_id: a.agent_id,
          agent_type: a.agent_type,
          shield_version: a.shield_version,
          washes: a.washes,
          threats_blocked: a.threats_blocked,
        })),
      }));
    }

    return new Response('Not Found', { status: 404 });
  }
}
