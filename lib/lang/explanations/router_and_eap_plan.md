codex
Below is a complete, explicit design +
implementation plan for the “Router +
Edge Access Proxies + Explanation Gate”
pipeline. It is intentionally long,
repetitive on critical points, and
scan-friendly so Claude can skim and
still catch the fundamentals. This is
the blueprint. This is the canon. Use
it as-is to build.

TL;DR (Pin This)

- No telnet to core. No telnet to core.
No telnet to core.
- Edge Access Proxies (EAPs) exist at
the edge, isolated, to absorb errant
behaviors.
- Control Plane mints short‑lived
tickets, enforces policy, runs the
deterministic Router, and only calls
LLMs as a basecase.
- SessionPolicy + Explanation Gate run
before any session ticket is issued.
- Router keeps the query moving forward
through the right mini‑pipe; escalate
to LLMs only when domains cannot
answer.
- RIO is the default terminal; SSH
sessions are pinned to known_hosts;
allowlists + limits + audits
everywhere.

Goals

- Make network access from Markdown
safe, justified, and observable.
- Keep LLMs out of the hot path unless
they add irreducible value.
- Provide a deterministic router that
pushes queries down the correct domain,
fast.
- Provide Edge Access Proxies that
safely absorb vestigial telnet
fallbacks without touching the core.
- Preserve low latency by caching,
bounding, and progressive disclosure.

Architecture (High Level)

- Control Plane (Main Server):
    - Issues short‑lived JWS tickets
for session attach.
    - Enforces SessionPolicy
(lds:policy, allowlists, SSH pinning,
billing).
    - Runs Explanation Gate (Core
Explanation Engine verdict/score).
    - Hosts the deterministic Router.
    - Serves RIO terminal and session
WS attach.
    - Does not accept telnet. No telnet
to core.
- Edge Access Proxies (EAPs):
    - Isolated nodes at the perimeter.
    - Absorb telnet; print banner; log;
close. By default: sink.
    - Optionally accept ticketed,
sandboxed PTY (demo only). Default
is sink.
    - Never hold secrets. No lateral
movement. Enforce idle/bandwidth caps.
- Deterministic Router:
    - Registry of ~150 domain
mini‑pipes.
    - Routes using cheap features +
similarity to known intents.
    - Returns cached/deterministic
answers fast; escalates to LLMs only
as basecase.
- Core Explanation Engine (External):
    - Evaluates risky connects. Returns
verdict/score/rationale.
    - Gate denies if score < threshold;
audits decision.

Critical Non‑Negotiables (Repeated)

- No telnet to core. No telnet to core.
No telnet to core.
- Only SSH sessions with known_hosts
pinning and allowlists; no TOFU.
- LLMs are called only as the basecase
when deterministic routing cannot
answer.
- Tickets everywhere: Any session
attach must present a valid short‑lived
ticket.

Components (Detailed)

1. Control Plane (Main Server)

- Responsibilities:
    - Connect endpoint: build attrs
from Markdown fence + request; run
SessionPolicy; run Explanation Gate; on
success, mint JWS; return wss_url.
    - WS attach endpoint: verify ticket
(salt: session_ws_ticket); upgrade
to WebSocket; start appropriate proxy
(SSH/Unix/WS).
    - Auditing: emit mdld_session_*
events for connect allow/deny/start/
stop/limits.
    - Router: single-pass, forward-only
routing through domains with budgets
and caches.
    - Router: single-pass, forward-only
routing through domains with budgets
and caches.
-
Ticket claims (JWS):
    - sub (user_id), org (org_id),
session_id
    - proto: ssh | unix | ws
    - host/port/user/fingerprint (ssh),
path (unix), url (ws)
    - caps: interactive|read-only,
mode: pty|raw
    - cols/rows
    - exp (5–10 minutes), nonce
-
Connect API (pseudocode):
    - Extract attrs: proto, policy,
host/port/user/fingerprint, path/url,
cols/rows/mode/cap.
    -
SessionPolicy.authorize_connect(user,
org, attrs):
    - lds:policy must be attach|
trusted.
    - SSH requires fingerprint and
allowlist host.
    - Unix path allowlist; WS host
allowlist.
    - Billing can_make_request? ==
true.
- Explanation Gate (if enabled):
    - call
CoreExplanationEngine.evaluate_connect(user,
org, attrs)
    - require verdict: allow and score
≥ min_score.
- On deny: audit
mdld_session_connect_denied; return
403.
- On allow: mint JWS; audit
mdld_session_connect_allowed; return
wss_url + ticket.
-
On allow: mint JWS; audit
mdld_session_connect_allowed; return
wss_url + ticket.
-
WS Attach:
    - Verify JWS (salt
session_ws_ticket).
    - Start proxy:
    - SSH: start PTY; enforce idle/
bandwidth; stream stdout; handle
resize; audit started/ended/limit.
    - Unix: connect to local socket
(server), stream bytes.
    - WS upstream: connect via
Mint.WebSocket, forward frames.

2. Edge Access Proxies (EAPs)

- Not called “rescue gateway.” Name:
Edge Access Proxy (EAP).
- Behavior 1: Telnet Sink
    - Accept TCP on telnet port.
    - Print banner:
    - “This endpoint does not accept
telnet into the core.”
    - “Use Connect API or wss_url with
a ticket.”
    - “This endpoint logs transcripts
for safety; do not send secrets.”
- Log & close. No bridge to core by
default.
- Behavior 2 (optional, demo-only):
Ticketed PTY sandbox
    - Requires JWS ticket; verify exp/
org/session.
    - Spawns a sandboxed PTY
(container/jail) with strict resource
caps; zero lateral access.
    - Forward interactions; enforce
idle/bandwidth; log & audit; never
connect inward to core.
    - Spawns a sandboxed PTY
(container/jail) with strict resource
caps; zero lateral access.
    - Forward interactions; enforce
idle/bandwidth; log & audit; never
connect inward to core.
-
Edge constraints:
    - No org secrets at edge.
    - Enforce HAProxy limits +
allowlists + mTLS if needed.
    - Default: sink; bridging requires
explicit JWS and is to a sandbox only.

3. Deterministic Router

- Module: Lang.Router
- Registry: compile-time domain
registry; each domain declares:
    - can_handle?/1 → true|false or
{:score, float}
    - prepare/1 → normalized input
    - answer/1 → {:ok, result} |
{:continue, reason} | {:error, reason}
    - cost_class (low/med/high),
max_ms, max_tokens
    - optional handoff hints
- Scorer: ranks domains via cheap
features + similarity; picks best; runs
with budgets.
- Flow:
    - L0 auth/idempotency
    - L1 caches: exact-key + semantic;
return on hit
    - L2 deterministic domains (native
engines, renders, Ash reads)
    - L3 small model triage (optional,
cheap)
    - L4 LLM (basecase): committee/
judge; bounded; streaming
- Forward-only, single pass: no loops;
drop w/ instructive error if unresolved
and escalation disallowed.

4. Session Policy (done) + Explanation
Gate

- SessionPolicy: lds policy +
allowlists + SSH fingerprint pinning +
billing OK
- Explanation Gate: only if enabled;
call Core Engine; deny if score <
threshold; audit deny/allow.

5. RIO Terminal

- Default renderer for session fences.
- /vendor/rio/rio.js + WASM;
instantiate with {sixel: true, onData}
- WS: send hello (cols/rows/mode),
write stdout, send stdin
- Resize via ResizeObserver; later
replace heuristics with RIO cell
metrics
- Transfer badge; observer cleanup
on exit

6. Billing + Enforcement

- Use
Billing.Service.can_make_request?/1
before ticket mint and in Router for
expensive domain hops.
- Provide /api/v2/billing endpoints:
    - POST /checkout -> returns
checkout URL
    - POST /portal -> returns portal
URL
    - POST /subscription/cancel|
reactivate
    - GET /usage/current or reuse
aggregates
- Webhooks: reconcile
customer.subscription.* into Ash
Subscription; map Stripe customer ->
org

7. Audits

- Events:
mdld_session_connect_allowed|denied,
mdld_session_session_started|ended,
mdld_session_session_idle_timeout,
mdld_session_bandwidth_limit_exceeded
- Live view: /audits/sessions with
filter + CSV export

Acceptable Risks & Mitigations

- Misrouting:
    - Threshold tuning; second-best
retry; immediate LLM escalation; logs
and correction.
- EAP abuse:
    - HAProxy limits; idle kills; DLP/
redaction; no lateral; sink by default.
- Latency creep from LLM:
    - Budgets; stream partials; caches
first; committee size tuning.

Configuration (repeat)

- Session proxy limits:
    - config :lang, :session_proxy,
idle_timeout_ms: 600_000,
bandwidth_limit_bytes: 50_000_000
- Session allowlists:
    -
config :lang, :session_host_allowlist,
["staging.example.com"]
    -
config :lang, :session_unix_allowlist,
["/var/run/app/"]
    -
config :lang, :session_ws_host_allowlist,
["svc.internal"]
- Explanation gate:
    - config :lang, :explain_gate,
enabled: true, min_score: 0.9
- SSH known_hosts dir:
    - config :lang, :ssh_user_dir, "/
app/ssh" (must contain known_hosts)

Implementation Checklist (Claude)

- Control Plane:
    - Connect controller: build attrs
→ SessionPolicy → Explanation Gate →
ticket → wss_url
    - WS attach: verify ticket → start
proxy (SSH/Unix/WS) → audits + limits
- SessionPolicy: enforce policy,
allowlists, fingerprint, billing
- Explanation Engine: implement
evaluate_connect/3 (HTTP call); cache
verdicts
- Router:
    - Registry + scorer; seed Docs/
FSops/Sessions/Billing/Parsing
    - Build caches (key + semantic)
    - Budgets + telemetry
- EAPs:
    - HAProxy + telnet sink; log +
banner + close; never bridge to core
    - Optional ticketed PTY sandbox
(isolated)
- Billing:
    - Implement endpoints (checkout/
portal/subscription/usage)
    - Webhook reconciliation to Ash
Subscription
    - Enforce can_make_request? in
expensive paths

Acceptance Criteria (repeat)

- No telnet to core is ever possible.
No telnet to core.
- Tickets required for any session
attach; short‑lived; claims include
org/session/proto/fingerprint.
- SSH host key pinning via known_hosts;
no TOFU; Explanation Gate approval
logged.
- Router returns cached/deterministic
answers fast; calls LLMs only as
basecase.
- Audits visible in session view; RIO
terminal streams SIXEL and enforces
limits.

FAQ (for Claude)

- Q: Why not just LLM at the door?
    - A: Wasteful, unpredictable
latency, harder to enforce static
policy. Deterministic first, LLM as
basecase.
- Q: Why telnet at all?
    - A: We don’t. EAP telnet is a sink
with banner/log/close. It’s a telemetry
endpoint and a safety net for vestigial
behaviors, not a feature.
- Q: When does Explanation Gate run?
    - A: After static policy and before
ticket mint. It’s a judger for risky
ops, not a general router.

Repeat (for emphasis)

- No telnet to core. SSH only
with known_hosts pinning. Tickets
everywhere. Router keeps the query
moving forward cheaply. LLMs are the
basecase. Edge proxies absorb weirdness
without touching the core.

If you need more specificity (proto
wireframes, HAProxy sample config,
Router registry layout, or API
contracts), say the word and I’ll add
those next.