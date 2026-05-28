# Gateway

A minimal personal v2ray (VMess over WebSocket+TLS) gateway you can stand up
with `terraform apply`. Comes with a tiny landing page that runs a latency +
throughput test and shows one country flag per active connection. Designed
for sharing with a handful of friends and family — not the public internet.

The repo ships **two parallel implementations** of the same gateway. Pick
one; they're independent.

## Which stack should I use?

|  | [`aws/`](./aws/README.md) | [`hetzner/`](./hetzner/README.md) |
|---|---|---|
| **CDN / edge** | CloudFront | Cloudflare (Free plan) |
| **Origin** | EC2 in `eu-central-1` (Frankfurt) | Hetzner Cloud VM in `fsn1` (Falkenstein) |
| **Domain required?** | **No** — uses the default `*.cloudfront.net` | **Yes** — needs a domain you own, on Cloudflare |
| **Country flag lookup** | `CloudFront-Viewer-Country` header (built-in, free) | Local MMDB (one-time signup at IPinfo / DB-IP) |
| **Idle cost** | ~$21 / month (EC2 + IPv4 + EBS) | ~€5 / month (cx23 + IPv4) |
| **Best when** | You have no domain and AWS is reachable from your users' ISP. | AWS IPs are blocked at your users' ISP (e.g. Iran). |

**Short answer:**

- If your users can reach AWS, the **AWS stack** is simpler — no domain, no
  signup beyond AWS itself.
- If your users sit behind an ISP that filters AWS (the common case in
  Iran), the **Hetzner + Cloudflare stack** is the one to use — Cloudflare's
  IPs are generally not blocked.

## Repo layout

```
aws/
  terraform/      AWS root module (eu-central-1).
  site/           Static site, uploaded to S3.
  README.md       Deploy guide for the AWS stack.
  ARCHITECTURE.md
hetzner/
  terraform/      Hetzner + Cloudflare root module.
  site/           Static site, baked into user-data and served from nginx.
  README.md       Deploy guide for the Hetzner stack — includes the
                  domain-onto-Cloudflare migration steps and the country
                  flag MMDB setup.
CLAUDE.md         Notes for any future Claude session working in this repo.
```

The two stacks share no Terraform state and don't depend on each other. You
can run both at once if you want to A/B them, but most users only need one.

## Common shape (both stacks)

- Single VM running `nginx` + `v2ray` (VMess over WebSocket on a configurable
  path, default `/stream`).
- A static landing page on `/` with:
  - **Run test** → measures latency (`/ping`) and throughput
    (`/speedtest`, a 5 MB random payload that bypasses any CDN cache).
  - Live host-stats panel (`/stats.json`) with CPU, memory, throughput, and
    one country flag per active connection.
- One credential — a `random_uuid.vmess_id` baked into both the server
  config and the `vmess://…` share link.
- Generated outputs: `vmess-share.txt` and `client-config.json` next to
  the `terraform/` dir of whichever stack you applied. Both gitignored.

## Prerequisites for either stack

- Terraform ≥ 1.5 (the repo pins `1.5.1` in `.tool-versions`).
- A v2ray client on the consuming devices — v2rayN (Windows), v2rayNG
  (Android), Shadowrocket (iOS), v2rayU (macOS), or anything that takes a
  `vmess://` URL.

Stack-specific prerequisites (AWS account / Hetzner + Cloudflare accounts +
tokens) are documented in each stack's README.

## See also

- [aws/README.md](./aws/README.md) — deploy and operate the AWS stack.
- [hetzner/README.md](./hetzner/README.md) — deploy and operate the
  Hetzner + Cloudflare stack, including the one-time DNS migration.
- [aws/ARCHITECTURE.md](./aws/ARCHITECTURE.md) — diagram and design notes
  for the AWS CloudFront-in-front-of-EC2 layout.
- [CLAUDE.md](./CLAUDE.md) — long-form notes about the repo (config
  invariants, gotchas, what *not* to change without thinking).
