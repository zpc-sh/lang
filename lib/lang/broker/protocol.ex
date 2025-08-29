defmodule Lang.Broker.Protocol do
  @moduledoc """
  Behaviour for pluggable broker protocols (e.g., MCP, DAP, custom JSON‑RPC).

  A protocol implementation owns the semantics for:
  - handshake/capabilities
  - mapping method/tool calls to internal services
  - formatting results/errors for clients

  Transport (TCP/WS/STDIO) is handled by the broker; protocol sees decoded
  JSON‑RPC maps and returns response maps.
  """

  @type session_state :: term()
  @type json :: map()

  @callback name() :: String.t()

  @doc """
  Initialize the protocol for a new session. `params` contains client info
  from the initialize request (if applicable).
  """
  @callback init(params :: json()) :: {:ok, session_state(), capabilities :: json()} | {:error, term()}

  @doc """
  Handle a request (expects a response) and return a result map or an error
  tuple. The broker will wrap it into a JSON‑RPC response.
  """
  @callback handle_request(method :: String.t(), params :: json(), session :: session_state()) ::
              {:ok, json(), session_state()} | {:error, integer(), String.t(), json(), session_state()}

  @doc """
  Handle a notification (no response expected). Return the (possibly updated)
  session state.
  """
  @callback handle_notification(method :: String.t(), params :: json(), session :: session_state()) ::
              {:ok, session_state()} | {:error, integer(), String.t(), json(), session_state()}

  @doc """
  Optional tools listing for protocols that expose tools (e.g., MCP).
  """
  @callback tools(session :: session_state()) :: list(map())

  @optional_callbacks tools: 1
end

