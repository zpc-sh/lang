# Wireframes and Data Models for Router + EAP Pipeline

This document provides visual wireframes and detailed data models to further clarify the "Router + Edge Access Proxies + Explanation Gate" pipeline design.

## 1. User Interaction Wireframes

These wireframes illustrate the key user-facing interactions within the system, particularly around session initiation and the RIO terminal experience.

### 1.1. Session Initiation Flow

**Step 1: User Markdown Input**
```
User's Markdown Document
----------------------------
... other content ...

```session:ssh
host: staging.example.com
user: myuser
```

... more content ...
----------------------------
```
*   **Actor:** User (via Markdown editor/rendered page).
*   **Action:** The user writes or interacts with a Markdown document containing a session fence (e.g., ```session:ssh).

**Step 2: Connect API Request**
*   **Actor:** Browser/Client Application (triggered by interacting with the rendered fence).
*   **Action:** An HTTP POST request is made to the Control Plane's `/api/v2/session/connect` endpoint.
*   **Request Payload:**
    ```json
    {
      "proto": "ssh",
      "host": "staging.example.com",
      "user": "myuser",
      "cols": 80,
      "rows": 24,
      "mode": "pty",
      "cap": "interactive"
    }
    ```
*   *(Internally, the Control Plane runs SessionPolicy and Explanation Gate).*

**Step 3: Ticket & Redirect Response**
*   **Actor:** Control Plane.
*   **Action:** If authorized, responds with a ticket and WebSocket URL.
*   **Response Payload:**
    ```json
    {
      "wss_url": "wss://api.example.com/api/v2/session/ws?ticket=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      "ticket": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
    }
    ```

**Step 4: WebSocket Attachment**
*   **Actor:** Browser/Client Application.
*   **Action:** Initiates a WebSocket connection to the `wss_url` provided in the previous step.

**Step 5: Session Starts (RIO Terminal Opens)**
*   **Actor:** Browser/Client Application.
*   **Action:** The RIO terminal component is instantiated and attached to the WebSocket stream. The user sees the terminal interface.
*   **UI Element (Conceptual):**
    ```
    +--------------------------------------------------+
    | RIO Terminal (staging.example.com)              |
    |--------------------------------------------------|
    | Last login: Fri Aug 29 10:00:00 2025 from ...   |
    | myuser@staging:~$ _                             |
    |                                                 |
    |                                                 |
    |                                                 |
    |                                                 |
    +--------------------------------------------------+
    | [Resize Handle] [Transfer Badge]                |
    +--------------------------------------------------+
    ```
*   *The terminal streams output from the SSH session and sends user input back.*

### 1.2. Telnet Sink Interaction (Edge Access Proxy)

**Step 1: Errant Telnet Connection**
*   **Actor:** Legacy Client/User.
*   **Action:** Attempts to connect via `telnet eap.example.com 23`.

**Step 2: EAP Response**
*   **Actor:** Edge Access Proxy.
*   **Action:** Accepts the connection, prints a banner, logs the attempt, and closes the connection.
*   **Terminal Output (Client Side):**
    ```
    Trying 192.0.2.1...
    Connected to eap.example.com.
    Escape character is '^]'.
    This endpoint does not accept telnet into the core.
    Use Connect API or wss_url with a ticket.
    This endpoint logs transcripts for safety; do not send secrets.
    Connection closed by foreign host.
    ```

## 2. Data Models

These models define the core data structures and configurations used by the system.

### 2.1. Session Ticket (JWS Claims)

This represents the structure of the claims embedded within the JWS ticket minted by the Control Plane.

```json
{
  "sub": "user_123",                 // User ID
  "org": "org_456",                  // Organization ID
  "session_id": "sess_789",          // Unique Session Identifier
  "proto": "ssh",                    // Protocol (ssh, unix, ws)
  "host": "staging.example.com",     // SSH Host (if proto=ssh)
  "port": 22,                        // SSH Port (if proto=ssh)
  "user": "myuser",                  // SSH User (if proto=ssh)
  "fingerprint": "SHA256:...",       // SSH Host Key Fingerprint (base64, if proto=ssh)
  "path": "/var/run/app.sock",       // Unix Socket Path (if proto=unix)
  "url": "wss://upstream.example.com", // Upstream WS URL (if proto=ws)
  "caps": "interactive",             // Capabilities (interactive, read-only)
  "mode": "pty",                     // Mode (pty, raw)
  "cols": 80,                        // Terminal Columns
  "rows": 24,                        // Terminal Rows
  "exp": 1751345678,                 // Expiration Timestamp (Unix)
  "nonce": "abc123def456"            // Nonce for uniqueness
}
```

### 2.2. Explanation Gate Verdict

The structure of the response from the Core Explanation Engine.

```json
{
  "verdict": "allow",                // Decision (allow, deny, uncertain)
  "score": 0.92,                     // Confidence Score [0.0, 1.0]
  "rationale": "Host is in known allowlist and user has high trust score." // Human-readable reason
}
```

### 2.3. Router Domain Handler (Conceptual Elixir Spec)

This outlines the expected structure and callbacks for a domain handler registered with the `Lang.Router`.

```elixir
defmodule Lang.Router.DomainHandler do
  @type input :: term()
  @type prepared_input :: term()
  @type result :: term()
  @type reason :: term()

  @doc "Can this domain handle the input? Returns true/false or a scored match."
  @callback can_handle?(input()) :: true | false | {:score, float()}

  @doc "Prepare the input for processing (e.g., parse, normalize)."
  @callback prepare(input()) :: prepared_input()

  @doc "Execute the domain's logic and return an answer."
  @callback answer(prepared_input()) :: {:ok, result()} | {:continue, reason()} | {:error, reason()}

  @doc "Indicates the computational cost class."
  @callback cost_class() :: :low | :medium | :high

  @doc "Maximum execution time in milliseconds."
  @callback max_ms() :: integer()

  @doc "Maximum tokens (for LLM domains)."
  @callback max_tokens() :: integer()

  # Optional callback for hints on handoff to another domain
  # @callback handoff_hints(prepared_input()) :: [domain_name :: atom()]
end
```

### 2.4. Configuration Snippets

Key configuration parameters that will be used across the system.

**Elixir Config (`config/runtime.exs` or similar):**
```elixir
config :lang, :session_proxy,
  idle_timeout_ms: 600_000,           # 10 minutes
  bandwidth_limit_bytes: 50_000_000   # 50 MB

config :lang, :session_host_allowlist, [
  "staging.example.com",
  "prod-internal.example.com"
]

config :lang, :session_unix_allowlist, [
  "/var/run/app.sock",
  "/tmp/debug.sock"
]

config :lang, :session_ws_host_allowlist, [
  "svc.internal"
]

config :lang, :explain_gate,
  enabled: true,
  min_score: 0.9

config :lang, :ssh_user_dir, "/app/ssh" # Must contain `known_hosts` file

# Billing Service Stub/Real Config
config :lang, :billing_service,
  module: Lang.Billing.Service, # Or a mock for dev
  can_make_request?: &Lang.Billing.Service.can_make_request?/1
```

**HAProxy Config Snippet (for EAP):**
```haproxy
# Edge Access Proxy (EAP) - Telnet Sink
frontend eap_telnet
    bind *:23
    mode tcp
    # Log the connection attempt
    tcp-request inspect-delay 5s
    tcp-request content accept if TRUE
    # Print banner and close. This is a simplified representation.
    # A real setup might use a custom program or Lua script for this.
    # For pure HAProxy, a 'tcp-request content reject' is the closest,
    # but printing a custom banner requires more complex scripting.
    # This snippet focuses on the binding and basic structure.
    default_backend eap_telnet_sink

backend eap_telnet_sink
    mode tcp
    # This backend would ideally connect to a service that prints the banner and closes.
    # HAProxy alone cannot easily print custom text and close.
    # For demonstration, we show a placeholder.
    server sink 127.0.0.1:9999 check

# Edge Access Proxy (EAP) - Optional Ticketed PTY (Demo)
# This would be a separate frontend, e.g., on a different port like 2222,
# handling SSH connections and verifying tickets before proxying to a sandbox.
# A more complex setup involving SSH libraries would be needed here.
# This is a conceptual representation.
frontend eap_ssh_demo
    bind *:2222
    mode tcp
    # Logic to intercept SSH handshake, verify ticket, then proxy
    # This is highly non-trivial in pure HAProxy and would likely require
    # a custom proxy or a more advanced load balancer with scripting.
    # Placeholder for the idea.
    default_backend eap_ssh_sandbox_backend

backend eap_ssh_sandbox_backend
    mode tcp
    # Pool of sandboxed PTY servers
    server sandbox1 10.0.1.10:22 check
    server sandbox2 10.0.1.11:22 check
```

This document, along with the plan and API contracts, provides a comprehensive view of the system's structure, user interactions, and data flow.