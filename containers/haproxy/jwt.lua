-- jwt.lua (example) - requires a lua-jwt lib providing JWT and jwk verification helpers
-- This is a stub showing structure. For production, vendor a tested lua-jwt library.

local http = require('socket.http')
local json = require('dkjson')

local jwks_cache = { keys = nil, ts = 0, ttl = 300 }
local jwks_url = os.getenv('JWKS_URL') or 'http://host.docker.internal:4000/.well-known/jwks.json'

local function fetch_jwks()
  local now = os.time()
  if jwks_cache.keys and (now - jwks_cache.ts) < jwks_cache.ttl then
    return jwks_cache.keys
  end
  local body, code = http.request(jwks_url)
  if code ~= 200 then return nil end
  local obj = json.decode(body)
  jwks_cache.keys = obj
  jwks_cache.ts = now
  return obj
end

local function verify_jwt(token)
  -- TODO: replace with real RS256 verification using jwks (kid-based key selection)
  -- This stub always returns false; production must validate signature & exp
  return false, { reason = 'stub' }
end

core.register_action('jwt_verify', { 'http-req' }, function(txn)
  local upgrade = txn.sf:req_hdr('Upgrade') or ''
  if upgrade:lower() ~= 'websocket' then
    txn:set_var('txn.jwt_status', 'skip')
    return
  end
  local proto = txn.sf:req_hdr('Sec-WebSocket-Protocol') or ''
  local token = nil
  for part in string.gmatch(proto, '([^, ]+)') do
    if part ~= 'lsp' and part ~= '' then token = part break end
  end
  if not token or token == '' then
    local q = txn.sf:req_fhdr('query') or ''
    token = q:match('ticket=([^&]+)')
  end
  if not token then
    txn:set_var('txn.jwt_status', 'deny')
    return
  end
  local jwks = fetch_jwks()
  if not jwks then
    txn:set_var('txn.jwt_status', 'deny')
    return
  end
  local ok, claims = verify_jwt(token)
  if not ok then
    txn:set_var('txn.jwt_status', 'deny')
    return
  end
  txn:set_var('txn.jwt_org', claims['org'] or '')
  txn:set_var('txn.jwt_status', 'allow')
end)

