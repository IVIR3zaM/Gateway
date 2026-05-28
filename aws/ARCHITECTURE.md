# Architecture

```
                      ┌───────────────────────────────────────────────┐
                      │              CloudFront distribution          │
client ─── HTTPS ────▶│  cert: default *.cloudfront.net               │
                      │                                               │
                      │  /                  ──▶ S3 (private, OAC)     │
                      │  /ping              ──▶ EC2:80   (no cache)   │
                      │  /speedtest         ──▶ EC2:80   (no cache)   │
                      │  /stream  (WS)      ──▶ EC2:80   (no cache)   │
                      └───────────────────────────────────────────────┘
                                          │                │
                                          ▼                ▼
                              ┌────────────────────┐   ┌─────────────┐
                              │ S3 bucket          │   │ EC2 t3.micro│
                              │ index.html only    │   │ Frankfurt   │
                              └────────────────────┘   │             │
                                                       │ nginx :80   │
                                                       │  ├ /ping    │
                                                       │  ├ /speed…  │
                                                       │  └ /stream  │
                                                       │    └─▶ v2ray│
                                                       │      127… : │
                                                       │       10000 │
                                                       │  (VMess+WS) │
                                                       └─────────────┘
```

## Design choices

**Why CloudFront in front of EC2?**
- Free TLS via the default `*.cloudfront.net` cert — no domain to register, no
  cert renewal to manage.
- CloudFront supports WebSocket upgrades, which is all v2ray's `ws` transport
  needs.
- Lets the static site and the v2ray endpoint share one origin from the
  client's perspective — no CORS, no mixed content.

**Why nginx on EC2?**
- One process to handle three URL paths: `/ping`, `/speedtest`, and the
  WebSocket upgrade to v2ray on `127.0.0.1:10000`.
- v2ray stays bound to localhost, so the only thing public on :80 is nginx.

**Why VMess over WS (no TLS at v2ray)?**
- TLS terminates at CloudFront, which re-encrypts to nothing on the way to
  EC2 — but the EC2 origin is HTTP-only because adding a cert there would
  require a domain we don't own. The hop is internal AWS traffic.
- For a "share with friends" tunnel this is a fine tradeoff. Upgrade path:
  bring a real domain, ACM cert in `us-east-1`, switch CloudFront to it.

**Speed test**
- `/ping` measures round-trip latency via median of 5 small fetches.
- `/speedtest` serves a 5 MB random payload (configurable via
  `var.speedtest_mb`); the client times the full body to derive Mbps.
- Both bypass CloudFront cache so the user measures the actual EC2 → edge →
  client path, not a cached object.

## Out of scope (for now)

- Custom domain + ACM cert.
- SSH / SSM access to the instance (everything is wired up via `user_data`).
- Multiple users with per-client UUIDs.
- IPv6 client connectivity (CloudFront IPv6 is on; EC2 is IPv4 only).
- Restricting EC2 :80 ingress to the CloudFront managed prefix list.
