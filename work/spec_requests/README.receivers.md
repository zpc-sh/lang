Receiver Guide: Acknowledging Spec Requests (v0)

Location
- Place your acknowledgment at: `work/spec_requests/<request_id>/ack.json`
- Update status markers alongside it: `accepted.status`, `in_progress.status`, `implemented.status`, etc.

ack.json format
{
  "owner": "alice",
  "contact": "alice@example.org",
  "eta_iso8601": "2025-09-02T12:00:00Z",
  "branch": "feature/jsonld-c14n",
  "status": "accepted",              // accepted | in_progress | blocked
  "notes": "Starting work; drafting API surface.",
  "updated_at": "2025-08-31T15:05:00Z"
}

Status trail
- Create an empty file for the current step under the request folder:
- `accepted.status` (upon acknowledgement)
- `in_progress.status` (when coding begins)
- `implemented.status` (when implementation is merged)
- `rejected.status` (if declined)
- `blocked.status` (optional marker if blocked)

Workflow (suggested)
1) Accept: write `ack.json` + create `accepted.status`
2) Start: update `ack.json.status = in_progress` + add `in_progress.status`
3) Complete: update notes with PR/commit refs + add `done.status`

Notes
- Keep everything repo‑local and deterministic; avoid network webhooks.
- You can copy this README and use the sample `ack.example.json` as a starting point.
