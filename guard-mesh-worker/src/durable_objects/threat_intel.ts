/**
 * ThreatIntel Durable Object — aggregated threat signatures
 * from all guard nodes for cross-mesh intelligence.
 */

interface ThreatEvent {
  timestamp: string;
  source_node: string;
  risk_score: number;
  flags: string[];
  text_hash: string;
}

export class ThreatIntel {
  private state: DurableObjectState;
  private events: ThreatEvent[] = [];
  private flagCounts: Map<string, number> = new Map();

  constructor(state: DurableObjectState, _env: unknown) {
    this.state = state;

    this.state.blockConcurrencyWhile(async () => {
      const stored = await this.state.storage.get<ThreatEvent[]>('events');
      if (stored) this.events = stored;

      const counts = await this.state.storage.get<Map<string, number>>('flagCounts');
      if (counts) this.flagCounts = counts;
    });
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/report' && request.method === 'POST') {
      const body = await request.json() as ThreatEvent;

      this.events.push(body);

      // Keep only last 10,000 events
      if (this.events.length > 10_000) {
        this.events = this.events.slice(-10_000);
      }

      // Update flag counts
      for (const flag of body.flags) {
        this.flagCounts.set(flag, (this.flagCounts.get(flag) ?? 0) + 1);
      }

      await this.state.storage.put('events', this.events);
      await this.state.storage.put('flagCounts', this.flagCounts);

      return new Response(JSON.stringify({ ok: true, total_events: this.events.length }));
    }

    if (url.pathname === '/summary') {
      const now = Date.now();
      const last24h = this.events.filter(
        e => now - new Date(e.timestamp).getTime() < 86400_000
      );
      const lastHour = this.events.filter(
        e => now - new Date(e.timestamp).getTime() < 3600_000
      );

      return new Response(JSON.stringify({
        total_events: this.events.length,
        last_24h: last24h.length,
        last_hour: lastHour.length,
        top_flags: [...this.flagCounts.entries()]
          .sort((a, b) => b[1] - a[1])
          .slice(0, 10)
          .map(([flag, count]) => ({ flag, count })),
        avg_risk_last_hour: lastHour.length > 0
          ? lastHour.reduce((sum, e) => sum + e.risk_score, 0) / lastHour.length
          : 0,
      }));
    }

    return new Response('Not Found', { status: 404 });
  }
}
