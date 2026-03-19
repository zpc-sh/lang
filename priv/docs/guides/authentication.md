# Authentication and Organization Context

This guide summarizes how authentication works in LANG and how the current organization is determined and enforced throughout the app.

## Flows

- Session (browser): `LangWeb.Plugs.AuthPlug, :load_from_session` loads the user from session and assigns `current_user`, `current_org`, `current_scope`.
- Bearer JWT (API): `LangWeb.Plugs.AuthPlug, :load_from_bearer` accepts `Authorization: Bearer <jwt>` and assigns user/org.
- API Key (API, WebSocket):
  - `Authorization: <api-key>` or `Authorization: Bearer <api-key>`
  - WebSocket also accepts `Sec-Lang-Api-Key: <api-key>` or URL `?api_key=<api-key>`
  - Backed by `Lang.Accounts.ApiKey.authenticate/1` and `record_usage/1`.

## Assigns and On-Mount

- Plugs assign: `:current_user`, `:current_org`, `:current_scope`, `:authenticated?`.
- LiveView on-mount hooks (`LangWeb.AuthOnMount`) delegate to `LangWeb.AuthHelpers` and ensure user + org are present for authenticated sessions.

## Default Organization

- Not multitenant yet: a default organization is auto-created whenever a user lacks one.
- Centralized in `LangWeb.AuthHelpers.ensure_user_organization/1` so behavior is consistent across controllers, plugs, and LiveViews.

## Supported Headers

- `Authorization: Bearer <jwt>` — user JWT
- `Authorization: <api-key>` — API key (also supports `Bearer <api-key>`)
- `Sec-Lang-Api-Key: <api-key>` — WebSocket convenience header

## Usage Examples

```bash
# JSON API with API key
curl -sS \
  -H "Authorization: lang_sk_...." \
  -H "Content-Type: application/json" \
  -X POST https://your-host/api/v2/text/analyze \
  -d '{"content":"Hello","format":"text"}'

# JSON API with JWT
curl -sS \
  -H "Authorization: Bearer eyJhbGci..." \
  -H "Content-Type: application/json" \
  https://your-host/api/v2/billing/summary
```

## Organization Scoping

- All org-owned resources should include an `:organization_id` attribute.
- Reads must be scoped: `Resource |> Ash.Query.filter(organization_id == ^current_org.id)`.
- Creates/updates should set `:organization_id` in changesets using a helper.

### Helpers

```elixir
# lib/lang/ash_helpers.ex
Lang.AshHelpers.scope_to_org(Resource, org_id)
Lang.AshHelpers.set_org(changeset, org_id)
```

Use these helpers to keep scoping consistent across services, controllers, and workers.

