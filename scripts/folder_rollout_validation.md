# Folder Rollout Validation (one‑pager)

Set env first (adjust as needed):

- `export FOLDER_URL=http://127.0.0.1:7070`
- `export FOLDER_TOKEN=...`  # PAT/API key, if you have one
- `export FOLDER_OWNER=acme`
- `export FOLDER_REPO=ai/memory/foundation`
- `export FOLDER_REFERENCE=latest`  # or sha256:...
- `export FOLDER_DIGEST=sha256:...` # blob digest from manifest
- `export FOLDER_TEAM_ID=11111111-2222-3333-4444-555555555555`
- `export FOLDER_WORKSPACE_ID=00000000-0000-0000-0000-000000000000`
- `export FOLDER_PATH=README.md` # path inside VFS workspace

## Registry Handshake

```bash
curl -sS -i "$FOLDER_URL/registry/v2"
```

Expect `200 OK`.

## Get Manifest (with PAT or WWW‑Authenticate challenge)

```bash
curl -sS -H "Authorization: Bearer $FOLDER_TOKEN" \
  "$FOLDER_URL/registry/v2/$FOLDER_OWNER/$FOLDER_REPO/manifests/$FOLDER_REFERENCE" | jq .
```

If 401 with `WWW-Authenticate`, mint a token:

```bash
SCOPE="repository:$FOLDER_OWNER/$FOLDER_REPO:pull"
curl -sS -X POST "$FOLDER_URL/api/v1/auth/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode scope="$SCOPE" \
  --data-urlencode audience=registry.folder.sh | tee /tmp/folder_token.json
ACCESS=$(jq -r .access_token /tmp/folder_token.json)
```

Retry manifest:

```bash
curl -sS -H "Authorization: Bearer $ACCESS" \
  "$FOLDER_URL/registry/v2/$FOLDER_OWNER/$FOLDER_REPO/manifests/$FOLDER_REFERENCE" | jq .
```

## Get Blob (expect 200 inline or 307 redirect)

```bash
curl -sS -i -H "Authorization: Bearer ${ACCESS:-$FOLDER_TOKEN}" \
  "$FOLDER_URL/registry/v2/$FOLDER_OWNER/$FOLDER_REPO/blobs/$FOLDER_DIGEST" | sed -n '1,12p'
```

If 307, follow it:

```bash
LOC=$(curl -sS -i -H "Authorization: Bearer ${ACCESS:-$FOLDER_TOKEN}" \
  "$FOLDER_URL/registry/v2/$FOLDER_OWNER/$FOLDER_REPO/blobs/$FOLDER_DIGEST" | awk '/^Location:/ {print $2}' | tr -d '\r')
[ -n "$LOC" ] && curl -sS -I "$LOC"
```

## Registry Search

```bash
curl -sS "$FOLDER_URL/api/v1/registry/search?owner=$FOLDER_OWNER&repo=$FOLDER_REPO&q=&ann[sh.folder.ai.layerType]=foundation" | jq .
```

## VFS List & Read (team/workspace)

```bash
curl -sS "$FOLDER_URL/api/v1/teams/$FOLDER_TEAM_ID/workspaces/$FOLDER_WORKSPACE_ID/files" | jq .
```

```bash
curl -sS "$FOLDER_URL/api/v1/teams/$FOLDER_TEAM_ID/workspaces/$FOLDER_WORKSPACE_ID/files?path=$FOLDER_PATH" | jq .
```

Or JSON‑RPC (if exposed):

```bash
curl -sS "$FOLDER_URL/jsonrpc" -H 'Content-Type: application/json' -d @- <<'EOF'
{ "jsonrpc": "2.0", "id": 1, "method": "folder/fs.list", "params": { "teamId": "'$FOLDER_TEAM_ID'", "workspaceId": "'$FOLDER_WORKSPACE_ID'", "path": "." } }
EOF
```

---

Alternatively, run the scripted validator with Req:

```bash
mix run scripts/validate_folder.exs
```
