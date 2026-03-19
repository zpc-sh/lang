# LANG LSP Agent Orchestration Quickstart

This guide shows how to orchestrate multiple agents (e.g., "codex" and "claude") through the LANG LSP JSON‑RPC API running on `localhost:4001`.

## Basics

- Transport: JSON‑RPC 2.0 over TCP with `Content-Length` framing (LSP style)
- Entry points (methods):
  - `lang.agent.spawn`, `lang.agent.delegate`, `lang.agent.coordinate`, `lang.agent.merge_results`, `lang.agent.terminate`, `lang.agent.get_status`
  - `lang.orchestration.start`, `lang.orchestration.status`, `lang.orchestration.cancel`

## Spawn “codex” and “claude”

```
{"jsonrpc":"2.0","id":1,"method":"lang.agent.spawn","params":{
  "capabilities":["analysis","single_file_edit"],
  "constraints":{"tokens":20000},
  "metadata":{"name":"codex"}
}}

{"jsonrpc":"2.0","id":2,"method":"lang.agent.spawn","params":{
  "capabilities":["analysis","multi_file_coordination"],
  "constraints":{"tokens":40000},
  "metadata":{"name":"claude"}
}}
```

Response contains `result.agent_id` (UUID). Save both IDs.

Note: If you include `metadata.name` (e.g., "codex", "claude") when spawning, LANG will set the agent's canonical `name` accordingly. Orchestration preferences use these names to prioritize agents for certain tasks (e.g., prefer "codex" for compute‑heavy, prefer "claude" for coordination).

## Delegate a Task

```
{"jsonrpc":"2.0","id":3,"method":"lang.agent.delegate","params":{
  "agent_id":"<codex-id>",
  "task":{
    "type":"analysis",
    "analysis_type":"explain_intent",
    "content":"defmodule Demo do\n  def run(x), do: x+1\nend"
  }
}}
```

## Coordinate Multiple Agents

Fanout strategy (both agents work in parallel):

```
{"jsonrpc":"2.0","id":4,"method":"lang.agent.coordinate","params":{
  "agent_ids":["<codex-id>","<claude-id>"],
  "task":{
    "type":"analysis",
    "analysis_type":"explain_why",
    "content":"<your code or text>",
    "strategy":"fanout"
  }
}}
```

First‑success strategy:

```
{"jsonrpc":"2.0","id":5,"method":"lang.agent.coordinate","params":{
  "agent_ids":["<codex-id>","<claude-id>"],
  "task":{
    "type":"analysis",
    "content":"<your code or text>",
    "strategy":"first_success"
  }
}}
```

Map‑reduce strategy (aggregates successful payloads then reduces):

```
{"jsonrpc":"2.0","id":6,"method":"lang.agent.coordinate","params":{
  "agent_ids":["<codex-id>","<claude-id>"],
  "task":{
    "type":"analysis",
    "content":"<your code or text>",
    "strategy":"map_reduce"
  }
}}
```

## Workflow Orchestration

Start and track a workflow from LSP:

```
{"jsonrpc":"2.0","id":7,"method":"lang.orchestration.start","params":{
  "workflow":{"kind":"text-docs-refresh"}
}}

{"jsonrpc":"2.0","id":8,"method":"lang.orchestration.status","params":{
  "workflow_id":"<id-from-start>"
}}
```

Cancel:

```
{"jsonrpc":"2.0","id":9,"method":"lang.orchestration.cancel","params":{"workflow_id":"<id>"}}
```

## Tips

- Prefer "codex" for compute‑heavy single‑file edits; prefer "claude" for higher‑level coordination.
- Long‑running tasks should be queued (Oban) via orchestration rather than run synchronously.
- For filesystem operations, always use native NIFs (`Lang.Native.FSScanner`).

Preference heuristics:
- Compute‑heavy (e.g., `type: "generation"`, `analysis_type: "optimization"`, or `goal` contains "optimiz") → prioritize agents named "codex" and with `:single_file_edit`/`:analysis` capabilities.
- Coordination‑heavy (e.g., `type: "coordination"` or strategies `fanout`/`map_reduce`) → prioritize agents named "claude" and with `:multi_file_coordination` capability.

## Local Sanity Check

Use the harness to start a time‑limited LSP server and send `initialize`:

```
scripts/lsp_harness.sh
```

Then pipe a JSON‑RPC frame to `nc 127.0.0.1 4001`.
