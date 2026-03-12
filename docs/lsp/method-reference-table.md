# LSP Method Reference Table

**Complete LSP implementation reference for development**

| Method | Status | Priority | Type | Description | Implementation File | Extension |
|--------|--------|----------|------|-------------|-------------------|-----------|
| **STANDARD LSP LIFECYCLE** |
| `initialize` | ✅ | Critical | LSP | Initialize server with client capabilities | `lib/lang/rpc/router.ex:10` | Standard |
| `initialized` | ❌ | High | LSP | Notification that client is ready | _Not implemented_ | Standard |
| `shutdown` | ✅ | Critical | LSP | Graceful shutdown request | `lib/lang/rpc/router.ex:33` | Standard |
| `exit` | ❌ | High | LSP | Force server exit | _Not implemented_ | Standard |
| **DOCUMENT SYNC** |
| `textDocument/didOpen` | 🚧 | Critical | LSP | Document opened in editor | `lib/lang/lsp/server.ex:444` | Standard |
| `textDocument/didChange` | 🚧 | Critical | LSP | Document content changed | `lib/lang/lsp/server.ex:474` | Standard |
| `textDocument/didSave` | ❌ | High | LSP | Document saved to disk | _Not implemented_ | Standard |
| `textDocument/didClose` | 🚧 | Medium | LSP | Document closed in editor | `lib/lang/lsp/server.ex:511` | Standard |
| `textDocument/willSave` | ❌ | Low | LSP | About to save document | _Not implemented_ | Standard |
| `textDocument/willSaveWaitUnt
