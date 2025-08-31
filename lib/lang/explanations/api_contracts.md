# API Contracts for Router + EAP Pipeline

This document defines the explicit API contracts for the components within the "Router + Edge Access Proxies + Explanation Gate" pipeline. These contracts are designed to be clear, versioned, and enforceable, ensuring deterministic behavior and safe interaction between services.

## 1. Control Plane APIs

### 1.1. Connect Endpoint (`POST /api/v2/session/connect`)

**Purpose:** Initiates a session request. Authenticates the user, evaluates policies and explanations, and if successful, mints a short-lived JWS ticket for use with the WS Attach endpoint.

**Request Body (Markdown Fence Attributes):**

```json
{
  "proto": "ssh | unix | ws",
  "host": "string (for ssh)", // Optional based on proto
  "port": "integer (for ssh)", // Optional based on proto
  "user": "string (for ssh)", // Optional based on proto
  "fingerprint": "string (for ssh, base64 encoded)", // Optional based on proto
  "path": "string (for unix)", // Optional based on proto
  "url": "string (for ws)", // Optional based on proto
  "cols": "integer",
  "rows": "integer",
  "mode": "pty | raw",
  "cap": "interactive | read-only"
}
```

**Response (Success - 200 OK):**

```json
{
  "wss_url": "string (WebSocket URL for attachment)",
  "ticket": "string (JWS token)"
}
```

**Response (Failure - 403 Forbidden):**
*   **Reason:** SessionPolicy denied the request or Explanation Gate score was below threshold.
*   **Body:** `{ "error": "Forbidden", "reason": "..." }`
*   **Audit Event:** `mdld_session_connect_denied`

**Authentication:** Standard API authentication (e.g., Bearer token).

**Authorization:** Enforced by `SessionPolicy`.

**Process (Pseudocode):**
1.  `attrs = extract_attributes(request_body)`
2.  `if not SessionPolicy.authorize_connect(current_user, current_org, attrs):`
    *   `emit_audit(mdld_session_connect_denied, reason: "Policy")`
    *   `return 403, { error: "Forbidden", reason: "Policy check failed" }`
3.  `if config.explain_gate.enabled:`
    *   `verdict = CoreExplanationEngine.evaluate_connect(current_user, current_org, attrs)`
    *   `if verdict.score < config.explain_gate.min_score or verdict.verdict != "allow":`
        *   `emit_audit(mdld_session_connect_denied, reason: "Explanation")`
        *   `return 403, { error: "Forbidden", reason: "Explanation check failed" }`
4.  `ticket_claims = build_ticket_claims(current_user, current_org, session_id, attrs)`
5.  `jws_ticket = mint_jws(ticket_claims, salt="session_connect_ticket", ttl=5-10 mins)`
6.  `wss_url = "/api/v2/session/ws?ticket=#{jws_ticket}"`
7.  `emit_audit(mdld_session_connect_allowed)`
8.  `return 200, { wss_url: wss_url, ticket: jws_ticket }`


### 1.2. WS Attach Endpoint (`GET /api/v2/session/ws`)

**Purpose:** Upgrades an HTTP request to a WebSocket connection using a valid ticket and then proxies data to the target service (SSH, Unix socket, or upstream WebSocket).

**Query Parameters:**
*   `ticket` (string, required): A valid JWS ticket minted by the Connect endpoint.

**Headers:**
*   `Authorization`: Standard API authentication (fallback if ticket invalid or for audit).
*   `Upgrade`: `websocket`
*   `Connection`: `Upgrade`

**Response (Success - 101 Switching Protocols):**
*   **Headers:** `Upgrade: websocket`, `Connection: Upgrade`
*   **Body:** None (WebSocket stream begins)

**Response (Failure - 400 Bad Request):**
*   **Reason:** Missing or malformed `ticket`.
*   **Body:** `{ "error": "Bad Request", "reason": "Invalid or missing ticket" }`

**Response (Failure - 403 Forbidden):**
*   **Reason:** Expired, invalid, or otherwise unusable `ticket`.
*   **Body:** `{ "error": "Forbidden", "reason": "Ticket verification failed" }`

**Process (Pseudocode):**
1.  `jws_ticket = request.query_params.ticket`
2.  `claims = verify_jws(jws_ticket, salt="session_ws_ticket")`
3.  `if not claims or is_expired(claims):`
    *   `return 403, { error: "Forbidden", reason: "Invalid ticket" }`
4.  `proto = claims.proto`
5.  `case proto:`
    *   `ssh:` -> `start_ssh_proxy(claims)`
    *   `unix:` -> `start_unix_proxy(claims)`
    *   `ws:` -> `start_websocket_proxy(claims)`
6.  `emit_audit(mdld_session_session_started, session_id: claims.session_id)`
7.  `upgrade_to_websocket()`
8.  `// Proxy logic handles streaming I/O and closure`
9.  `// On proxy termination:`
10. `emit_audit(mdld_session_session_ended, session_id: claims.session_id)`


### 1.3. Billing Endpoints (`/api/v2/billing`)

**Purpose:** Manage subscriptions, access billing portal, and retrieve usage data.

**Endpoints:**

*   `POST /api/v2/billing/checkout`
    *   **Purpose:** Initiates a new subscription checkout process.
    *   **Request Body:** `{ "price_id": "string", "success_url": "string", "cancel_url": "string" }`
    *   **Response (200 OK):** `{ "checkout_url": "string (Stripe checkout URL)" }`

*   `POST /api/v2/billing/portal`
    *   **Purpose:** Generates a URL to access the customer billing portal.
    *   **Request Body:** `{ "return_url": "string" }`
    *   **Response (200 OK):** `{ "portal_url": "string (Stripe customer portal URL)" }`

*   `POST /api/v2/billing/subscription/cancel`
    *   **Purpose:** Cancels a subscription.
    *   **Request Body:** `{ "subscription_id": "string" }`
    *   **Response (200 OK):** `{ "status": "cancelled" }`

*   `POST /api/v2/billing/subscription/reactivate`
    *   **Purpose:** Reactivates a cancelled subscription.
    *   **Request Body:** `{ "subscription_id": "string" }`
    *   **Response (200 OK):** `{ "status": "active" }`

*   `GET /api/v2/billing/usage/current`
    *   **Purpose:** Retrieves current billing period usage metrics.
    *   **Response (200 OK):** `{ "metrics": { "sessions_used": integer, "bandwidth_used_bytes": integer, ... } }`

**Authentication & Authorization:** Standard API auth, user must have billing admin rights for the organization.

## 2. Core Explanation Engine API

### 2.1. Evaluate Connect (`POST /api/v1/explain/connect`)

**Purpose:** Evaluates the risk of a connection request and returns a verdict.

**Request Body (Mirrors Connect attrs):**

```json
{
  "user_id": "string",
  "org_id": "string",
  "request_attrs": {
    // Same structure as Connect endpoint request body
  }
}
```

**Response (Success - 200 OK):**

```json
{
  "verdict": "allow | deny | uncertain",
  "score": "float (0.0 to 1.0)",
  "rationale": "string (Human-readable explanation for the verdict)"
}
```

**Authentication:** Bearer token (specific to the Control Plane service).
**Authorization:** Service-to-service, restricted access.

## 3. Router Interface (Internal)

### 3.1. Domain Handler Specification

Domains registered with the `Lang.Router` must implement the following callbacks:

*   `can_handle?(input) :: true | false | {:score, float()}`:
    *   Determines if the domain can handle the input.
    *   Return `true` for a definitive match, `false` for no match, or `{:score, s}` for a probabilistic match with score `s`.
*   `prepare(input) :: prepared_input`:
    *   Normalizes and prepares the input for the `answer/1` function. May involve parsing, enrichment, etc.
*   `answer(prepared_input) :: {:ok, result} | {:continue, reason} | {:error, reason}`:
    *   Executes the domain's logic.
    *   `{:ok, result}`: A final, successful answer.
    *   `{:continue, reason}`: The domain cannot answer definitively; routing should continue.
    *   `{:error, reason}`: An error occurred within the domain.
*   `cost_class() :: :low | :medium | :high`:
    *   Indicates the computational cost/latency class of the domain.
*   `max_ms() :: integer()`:
    *   The maximum time (in milliseconds) the domain's `answer/1` should be allowed to run.
*   `max_tokens() :: integer()`:
    *   (For LLM-based domains) The maximum number of tokens the domain is allowed to consume.

### 3.2. Router Call

The router is invoked internally by the Control Plane after policy checks.

**Function Signature (Elixir-like pseudocode):**

```elixir
Lang.Router.route(input, context, opts \\ []) :: {:ok, result} | {:continue, reason} | {:error, reason}
```

**Parameters:**
*   `input`: The raw user query or command.
*   `context`: A map containing session info (user_id, org_id, session_id, ticket_claims).
*   `opts`: Additional options (e.g., `allow_escalation: true`).

**Return Values:**
*   `{:ok, result}`: A final answer was determined, either deterministically or by an LLM.
*   `{:continue, reason}`: No domain could provide a final answer. This might lead to an LLM escalation if allowed.
*   `{:error, reason}`: An error occurred during routing or domain execution.

This document, combined with the main plan, forms the explicit contract for building the pipeline.