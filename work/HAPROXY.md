HAProxy (optional edge)

- TLS terminate + WS upgrade; proxy only Phoenix (443)
- Optional JWT verify (lua-jwt), RS256 JWK or HS256 secret
- Stick-table rate limit by org (extracted from JWT claim)

Sketch

frontend https
  bind :443 ssl crt /etc/ssl/site.pem
  acl is_ws hdr(Upgrade) -i websocket
  http-request use-service lua.jwt_verify if is_ws
  http-request set-var(req.org) lua.jwt_claim,org if is_ws
  stick-table type string size 100k expire 5m store http_req_rate(10s)
  http-request track-sc0 var(req.org) if is_ws
  acl rl_abuse sc_http_req_rate(0) gt 50
  http-request deny status 429 if rl_abuse
  use_backend phoenix_ws if is_ws
  default_backend phoenix

backend phoenix_ws
  server app 127.0.0.1:4000

backend phoenix
  server app 127.0.0.1:4000

Notes
- lua.jwt_verify should check signature + exp and set 401 on failure
- App still verifies; edge adds coarse protection
