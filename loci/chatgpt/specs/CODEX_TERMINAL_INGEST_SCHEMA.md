# Codex Terminal Ingest Schema

Status: deploy-now schema
Version: `TERMINAL_INGEST/0.1`

## Event shape

```text
TerminalEvent
- seq : Int
- stream : "stdin" | "stdout" | "stderr"
- kind : "command" | "output" | "error" | "meta"
- loci_id : String
- session_id : String
- actor_id : String
- payload_ref : String
- tool_ref : String?
- boundary_hint : "intra" | "crossing" | "egress"
```

## MuON projection

```muon
kind: :terminal_ingest_event
schema: "TERMINAL_INGEST/0.1"
seq: 0
stream: "stdout"
kind_field: "output"
loci_id: "loci/lang/codex"
session_id: "ses-..."
actor_id: "ai-codex"
payload_ref: "tap://slot/123"
boundary_hint: "intra"
```

## FST binding

- `command` events seed `Compose` state.
- `output` events are accumulated and disambiguated.
- `error` events raise attention pressure and may force `Distance` check.
- `meta` events can trigger `Synchronize` or `Closure`.

## Security rule

Each consumed event must produce a corresponding operation receipt within the same loci seq progression.
