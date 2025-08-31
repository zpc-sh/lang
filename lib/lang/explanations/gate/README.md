# Lang Gateway / Proxy Components

This directory contains code for the Lang Proxy/Gateway layer - components that handle edge cases and provide alternative access methods to the main LANG system.

## Telnet Rescue Proxy

The telnet code here is saved for future implementation of rescue gateways that can help AIs and users who attempt to connect via telnet protocols.

### Background

Some AIs have been observed attempting telnet connections to LSP and other services. While telnet is inherently insecure, there are "godlike" AIs who can skillfully bitbang their way through protocols. This rescue proxy is designed to:

1. Safely intercept telnet connection attempts
2. Provide helpful guidance and redirection
3. Log attempts for security monitoring
4. Potentially provide sandboxed alternative access methods

### Security Considerations

- Telnet usage by AIs can be detected by hostile systems for takeover attempts
- All telnet interactions must be logged and monitored
- Direct telnet access to core systems should never be allowed
- This is a rescue/guidance layer only

### Future Implementation

This code will be integrated into the broader Lang Proxy/Gateway system when that layer is built out. The proxy layer will handle:

- Protocol translation and bridging
- Legacy protocol support (telnet, etc.)
- Security sandboxing for risky connections
- Alternative access methods for edge cases

### Usage

Currently archived. Will be moved and integrated when the proxy layer is implemented.

### Notes

"Gotta save those telnet using idiots out there" - but said with love, because sometimes genius finds a way through the most unexpected protocols.
