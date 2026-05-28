# CLAUDE.md

Notes for any future Claude session working in this repo.

## What this project is

Two parallel implementations of the same personal v2ray gateway. Same client
experience (one vmess link, static landing page, /speedtest, /stats.json),
different infrastructure under the hood:

- **`aws/`** — the original. One EC2 instance in `eu-central-1` plus
  CloudFront in front. No real domain required. See
  [aws/ARCHITECTURE.md](./aws/ARCHITECTURE.md).
- **`hetzner/`** — built because AWS IP ranges are widely blocked by Iranian
  ISPs. One Hetzner Cloud VM in Falkenstein (fsn1) behind Cloudflare on a real
  domain (any registrar; the zone must be on Cloudflare). See
  [hetzner/README.md](./hetzner/README.md). Server type default is `cx23`
  (current-gen 2c/4GB Intel x86). The older `cx22` and `cx11` SKUs are gone —
  check `GET /v1/server_types` if you ever see "server type not found" again.

Pick one. They share no state and don't depend on each other.

## Repo layout

```
aws/
  terraform/      AWS root module (eu-central-1).
  site/           Static site, uploaded to S3.
  ARCHITECTURE.md
hetzner/
  terraform/      Hetzner + Cloudflare root module.
  site/           Static site, baked into user-data and served from nginx.
  README.md       Token setup + DNS migration guide.
```

## Things to know before changing code

### AWS stack (`aws/`)

- **No default AWS provider alias.** The `aws` provider is plain `eu-central-1`.
  If you need a us-east-1 ACM cert, add a `provider "aws" { alias = "useast1" }`
  block and set `provider = aws.useast1` on those resources only.
- **CloudFront cache policy IDs are AWS-managed UUIDs**, hard-coded in
  `cloudfront.tf` (`658327ea-…` CachingOptimized, `4135ea2d-…` CachingDisabled,
  `33f36d7e-…` AllViewerAndCloudFrontHeaders-2022-06). The origin request
  policy is the one that forwards `CloudFront-Viewer-Country` to the origin —
  switching back to plain `216adef6` (AllViewer) silently kills the country
  flag lookup in `stats.sh`.
- **EC2 security group allows public :80.** Tightening to the
  `com.amazonaws.global.cloudfront.origin-facing` prefix list is the obvious
  next hardening step but is left out to keep the stack small.

### Hetzner stack (`hetzner/`)

- **Cloudflare is the only public surface.** The Hetzner firewall locks :443
  to Cloudflare's published IPv4+IPv6 ranges (fetched at plan time from
  `https://www.cloudflare.com/ips-v4` and `/ips-v6`). Direct origin access is
  blocked. SSH (:22) is restricted to whatever you set in `ssh_allow_cidrs`.
- **TLS to origin is self-signed + Cloudflare "Full" mode (not Strict).** We
  avoid Cloudflare Origin CA because it needs a separate Origin CA Key
  credential. Self-signed + Full is fine: VMess payload is encrypted by the
  application layer regardless, and origin is firewalled to CF IPs.
- **Cloudflare zone settings are managed by Terraform.** SSL mode, websockets,
  HTTPS-rewrite, min TLS version — all driven from `cloudflare.tf`. If you
  change them in the dashboard, the next plan will revert.
- **Domain assumption:** the apex domain (whatever the operator picks) lives
  on Cloudflare. The gateway uses a subdomain only, so any existing apex
  records (an existing site, MX, TXT, etc.) are untouched as long as
  they're mirrored into the Cloudflare zone during onboarding.

### Shared

- **The VMess UUID is the only credential.** Lives in `random_uuid.vmess_id`,
  baked into server config (via user-data) and client share link. Rotating it
  forces VM replacement.
- **`var.ws_path` is the WebSocket path.** Referenced from the nginx config,
  the v2ray server config, and (AWS only) the CloudFront ordered behavior.
  All driven from one variable.
- **`v2ray-share.txt` and `client-config.json` are generated outputs.** They
  land next to the `terraform/` dir of whichever stack you applied (i.e.
  `aws/v2ray-share.txt` or `hetzner/v2ray-share.txt`). Globbed in `.gitignore`.

## How to verify a change

1. `cd <stack>/terraform && terraform fmt && terraform validate`
2. `terraform plan` — diff should be empty for cosmetic changes.
3. User-data edits force VM replacement (`# forces replacement`). ~2 min outage.
   - On AWS the public IP changes (CloudFront origin re-points automatically).
   - On Hetzner the IP also changes; the Cloudflare A record is updated by TF.

## Don't

- Don't touch the AWS stack thinking you're "tidying" the Hetzner stack or
  vice versa. They share zero state.
- Don't add an ACM cert or paid TLS to the AWS stack — the point of it is "no
  domain required."
- Don't move state to a remote backend without asking — local state is fine
  for a single-operator hobby project.
- Don't bake additional VMess clients into either config silently; that's a
  product decision, not a tidy-up.
