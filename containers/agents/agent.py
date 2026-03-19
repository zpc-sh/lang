import os, socket, json, sys

HOST = os.getenv("LSP_HOST", "host.docker.internal")
PORT = int(os.getenv("LSP_PORT", "4001"))
CLIENT_ID = os.getenv("CLIENT_ID", "client-unknown")
MCP_DEBUG_TOKEN = os.getenv("MCP_DEBUG_TOKEN", "")

# Allow overriding the opened document via env
URI = os.getenv("URI", "file:///w/demo.ex")
LANGUAGE_ID = os.getenv("LANGUAGE_ID", "elixir")
TEXT = os.getenv(
    "TEXT",
    "defmodule Demo do\n  def add(a,b), do: a + b\nend\n",
)


def send(sock, obj):
    body = json.dumps(obj, separators=(",", ":"))
    header = f"Content-Length: {len(body)}\r\n\r\n"
    sock.sendall(header.encode("utf-8") + body.encode("utf-8"))


def recv_some(sock, limit=8192, timeout=2.0):
    sock.settimeout(timeout)
    try:
        return sock.recv(limit)
    except Exception:
        return b""


def main():
    try:
        s = socket.create_connection((HOST, PORT), timeout=3.0)
    except Exception as e:
        print(f"[{CLIENT_ID}] ❌ connect failed: {e}", flush=True)
        sys.exit(1)

    print(f"[{CLIENT_ID}] ✅ connected to {HOST}:{PORT}", flush=True)

    # initialize
    init = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "processId": None,
            "rootUri": None,
            "capabilities": {},
            "clientInfo": {"name": CLIENT_ID, "version": "0.1"},
        },
    }
    send(s, init)
    print(f"[{CLIENT_ID}] 📤 initialize", flush=True)
    resp = recv_some(s)
    if resp:
        print(f"[{CLIENT_ID}] 📡 init resp: {resp[:200]!r}", flush=True)

    # initialized
    send(s, {"jsonrpc": "2.0", "method": "initialized", "params": {}})

    # Optional identify (for logs/correlation if your server supports it)
    if MCP_DEBUG_TOKEN:
        send(
            s,
            {
                "jsonrpc": "2.0",
                "method": "lang/tester/identify",
                "params": {"token": MCP_DEBUG_TOKEN, "clientId": CLIENT_ID},
            },
        )

    # didOpen a small buffer
    uri = URI
    text = TEXT
    send(
        s,
        {
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {
                "textDocument": {
                    "uri": uri,
                    "languageId": LANGUAGE_ID,
                    "version": 1,
                    "text": text,
                }
            },
        },
    )

    # optional full-document change for testing
    new_text = os.getenv("NEW_TEXT", "")
    if new_text:
        send(
            s,
            {
                "jsonrpc": "2.0",
                "method": "textDocument/didChange",
                "params": {
                    "textDocument": {"uri": uri, "version": 2},
                    "contentChanges": [{"text": new_text}],
                },
            },
        )

    # completion request
    send(
        s,
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "textDocument/completion",
            "params": {"textDocument": {"uri": uri}, "position": {"line": 1, "character": 25}},
        },
    )
    comp = recv_some(s, limit=16_384, timeout=2.0)
    if comp:
        print(f"[{CLIENT_ID}] 📡 completion resp: {comp[:400]!r}", flush=True)

    # didClose
    send(
        s,
        {
            "jsonrpc": "2.0",
            "method": "textDocument/didClose",
            "params": {"textDocument": {"uri": uri}},
        },
    )

    s.close()
    print(f"[{CLIENT_ID}] 🎉 done", flush=True)


if __name__ == "__main__":
    main()
