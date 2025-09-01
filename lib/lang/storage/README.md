# Lang.Storage Integration

This folder provides the Storage facade and adapters used by Lang and the DPA/Agent LSP protocol.

Key points:
- Facade `Lang.Storage` handles billing checks via `Lang.Billing.Service.can_make_request?/1` and emits `Lang.Events` with `folder_*` event types.
- Default adapter `Lang.Storage.LocalFS` uses native Rust NIFs (`Lang.Native.FSScanner`) for all filesystem operations.
- You can set `config :lang, :storage_adapter, Lang.Storage.Folder` to proxy to the Folder service via HTTP when ready.

API surface:
- `list/3`, `stat/2`, `read/3`, `preview/3`, `search/3`, `search_code/4`, `scan/2`, `write/4`, `move/3`, `delete/3`
- All functions accept a context map `%{organization_id:, user_id:, session_id:, root:}` for cross-billing and auth sharing.

LSP commands (stubs included):
- `lang.folder/list`, `lang.folder/stat`, `lang.folder/preview`
- Wire additional commands similarly and call `Lang.Storage` from handlers.

Safety:
- All paths are normalized and constrained under a workspace root before NIF calls.

