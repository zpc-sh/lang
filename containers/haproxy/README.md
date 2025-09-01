Dev HAProxy

Build and run a local HAProxy that proxies to the Phoenix app on :4000 and supports WS:

  docker build -t lang-haproxy-dev containers/haproxy
  docker run --rm -p 8080:8080 lang-haproxy-dev

Then access the app via http://localhost:8080 (WS endpoints proxy through).

Notes
- This is a minimal dev config without JWT verification.
- For RS256 JWT verification at the edge, ship a custom image with lua-jwt and load your JWK.
- In production, deploy a prebuilt and tuned package; only the config should vary per env.

Production
- Example config: `haproxy-prod.cfg` (expects `/usr/local/etc/haproxy/jwt.lua` and a JWK source)
- jwt.lua should:
  - Fetch and cache `/.well-known/jwks.json` (or read a mounted JWK)
  - Verify RS256 signatures on tickets from WS requests
  - Set `txn.jwt_org` for stick-table rate limiting
- Build your image with lua-jwt and jwt.lua, then mount haproxy-prod.cfg as your config
