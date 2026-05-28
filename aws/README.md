# AWS gateway

The original stack. One EC2 instance in Frankfurt fronted by CloudFront, which
also serves a tiny static landing page with a link-quality test. Designed to
be shared with a handful of friends and family, not the public internet.

**Use this stack if you don't have a domain** — CloudFront's default
`*.cloudfront.net` hostname gives you free TLS without registering or paying
for anything DNS-related. If you need to bypass blocked AWS IP ranges (e.g.
Iranian ISPs), see [`../hetzner/`](../hetzner/README.md) instead.

## What you get after `terraform apply`

- `https://<dist>.cloudfront.net/` — static page with a **Run test** button
  that measures latency and download throughput against the edge, plus a
  live host-stats panel with one flag per active connection.
- A `vmess://…` share link printed via `terraform output` and written to
  `aws/v2ray-share.txt` — paste into v2rayN / v2rayNG / Shadowrocket.
- A full `client-config.json` next to it for headless use.

## Prerequisites

- AWS credentials with permission to create EC2 / VPC subnet / S3 /
  CloudFront. The deploy commands below expect them under an
  `AWS_PROFILE=personal` named profile — use whatever profile name you
  prefer.
- Terraform `1.5.1` (pinned in `.tool-versions`).
- The default deploy region is `eu-central-1` (Frankfurt); override with
  `-var region=...`.

## Deploy

```bash
cd aws/terraform
terraform init                                          # one-time
AWS_PROFILE=personal terraform plan                     # diff preview
AWS_PROFILE=personal terraform apply                    # creates EC2 + S3 + CloudFront
AWS_PROFILE=personal terraform output -raw vmess_share_link
```

`apply` takes ~3–5 min (most of it is CloudFront creation). After it returns,
the share link is also written to `aws/v2ray-share.txt`, and a full
`client-config.json` is written next to it (both git-ignored).

The CloudFront distribution may take an additional minute or two to fully
propagate to all edges after the apply finishes. If `/ping` returns 504
immediately after apply, just wait a moment and retry.

### Picking a different region

```bash
AWS_PROFILE=personal terraform apply -var region=eu-west-1
```

…or export `TF_VAR_region=us-east-1`, or set it in
`aws/terraform/terraform.tfvars`. The `ps` (display name) baked into the
`vmess://` share link is `${name}-${region}` (e.g. `gateway-eu-central-1`),
so it's easy to tell multiple deployments apart in your v2ray client.

## Rotate credentials

The VMess UUID in the share link is the only credential. To rotate (e.g.
after sharing with someone you'd rather un-share with):

```bash
AWS_PROFILE=personal terraform taint random_uuid.vmess_id
AWS_PROFILE=personal terraform apply
```

This also forces an EC2 replacement (the UUID is baked into user-data), so
expect a ~2-minute outage on the v2ray endpoint. The static site stays up.

## Update the EC2 box without rotating the key

```bash
AWS_PROFILE=personal terraform taint aws_instance.v2ray
AWS_PROFILE=personal terraform apply
```

Same outage shape, but the same UUID / share link survives.

## Tear down

```bash
cd aws/terraform
AWS_PROFILE=personal terraform destroy
```

`destroy` is the canonical "stop charging me" — it removes the EC2 instance,
EBS volume, S3 bucket (and the `index.html` inside), CloudFront distribution
(slowest step — disabling a distribution takes ~3 min), and the public
subnet.

## Cost (rough, idle, `eu-central-1`, May 2026 on-demand pricing)

For a single instance left running 24/7 with light personal traffic:

| Item | Detail | ~Monthly |
|---|---|---|
| EC2 `t3.small` | $0.0228/hr × 730 hr | **$16.64** |
| Public IPv4 address | $0.005/hr × 730 hr (charged since Feb 2024) | **$3.65** |
| EBS 8 GB gp3 | $0.0952/GB-mo × 8 GB | **$0.76** |
| CloudFront egress | Always-free tier: 1 TB/mo + 10M HTTPS req | **$0.00** |
| EC2 → CloudFront egress | Free (CloudFront-origin transfer is not billed) | **$0.00** |
| S3 storage + requests | A handful of KB for `index.html` | **~$0.01** |
| Route 53 / ACM / DNS | None — uses the default `*.cloudfront.net` host | **$0.00** |
| **Total, idle** | | **≈ $21 / month** |

Notes:

- **Going over the CloudFront free tier** costs about $0.085/GB egress in
  EU/US (PriceClass_All ≈ +15% vs PriceClass_100). 100 GB above the free
  tier ≈ +$8.50/mo.
- **Different region**: prices above are Frankfurt. US regions (`us-east-1`,
  `us-west-2`) are 5–10% cheaper for EC2; Asia-Pacific regions (Tokyo,
  Singapore) run 15–25% more.
- **Stopped instance**: stopping the EC2 instance still bills the EBS volume
  and the public IPv4 reservation (~$4.40/mo). To stop charges entirely, run
  `terraform destroy`.

### Picking an instance size

| `instance_type` | vCPU | RAM | ~EC2 / mo | Notes |
|---|---|---|---|---|
| `t3.nano`   | 2 | 0.5 GB | **$3.80** | Too small — TLS + v2ray will swap/OOM under any real load. |
| `t3.micro`  | 2 | 1 GB   | **$7.60** | Free tier eligible on new accounts. Fine for 1–2 light users. |
| `t3.small` (default) | 2 | 2 GB | **$16.64** | Comfortable for a handful of friends/family. |
| `t3.medium` | 2 | 4 GB   | **$33.29** | Headroom for ~10 users; bursts handle short spikes. |
| `t3.large`  | 2 | 8 GB   | **$66.58** | Rarely needed unless you're saturating the CPU on TLS. |
| `c6i.large` | 2 | 4 GB   | **$62.05** | Sustained CPU (no burst credits) — pick if you saw `t3.*` throttling. |
| `c6i.xlarge`| 4 | 8 GB   | **$124.10** | Real bandwidth tier; only worth it if the network is the bottleneck. |

`t3.*` (burstable) is the right default for personal/shared use — the
gateway is idle most of the time and bursts when someone actually streams.
Switch to `c6i.*` only if `htop` on the box shows sustained 100% CPU.

## Interpreting the speed-test page

`/ping` is a small, uncached round trip to EC2 — gives you **latency**.
`/speedtest` is a 5 MB random payload served by EC2 with caching disabled
all the way through CloudFront — gives you **throughput**.

Because both bypass the CloudFront cache, the numbers reflect the path your
v2ray traffic actually takes (`client → CloudFront edge → EC2 in Frankfurt`).
If the page shows ~30 Mbps and a few hundred ms latency, that's roughly what
v2ray will give you. If it shows < 1 Mbps and multi-second latency, your ISP
is throttling AWS or you're being routed through a distant edge.

Tunables in `aws/terraform/variables.tf`:

| Variable | Default | What it controls |
|---|---|---|
| `instance_type` | `t3.small` | EC2 size. |
| `ws_path` | `/stream` | URL path v2ray's WebSocket lives at. |
| `speedtest_mb` | `5` | Size of the random payload served at `/speedtest`. |
| `region` | `eu-central-1` | AWS region for EC2 + S3 (CloudFront is global). |

## Country flags

The landing page shows one flag per active VMess connection. Country
detection on this stack uses **CloudFront's built-in `CloudFront-Viewer-Country`
header** — CloudFront geo-locates every request server-side and stamps the
2-letter code on the way to the origin. No external lookup, no API key,
no signup.

The plumbing:

1. The origin request policy on every EC2 behavior is
   `33f36d7e-…` (AWS-managed `AllViewerAndCloudFrontHeaders-2022-06`),
   which forwards `CloudFront-Viewer-Country` to nginx.
2. nginx logs that header per WS handshake to
   `/var/log/nginx/ws-handshake.log`.
3. `gw-stats.sh` reads distinct codes from the last 15 minutes, capped at
   the current count of established v2ray connections, and writes them to
   `/var/www/stats.json`.

Switching back to the plain `Managed-AllViewer` policy (`216adef6-…`)
silently kills this — the header stops being forwarded and every flag goes
white. If that ever happens, `cloudfront.tf` is where to look.

## See also

- [ARCHITECTURE.md](./ARCHITECTURE.md) — diagram and rationale for the
  CloudFront-in-front-of-EC2 layout.
- [../hetzner/README.md](../hetzner/README.md) — alternative stack with a
  real domain + Cloudflare, for users in countries where AWS IPs are blocked.
- [../CLAUDE.md](../CLAUDE.md) — notes for any future Claude session
  working in this repo.
