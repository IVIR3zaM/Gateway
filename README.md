# Gateway

A minimal personal v2ray gateway on AWS — one EC2 instance in Frankfurt,
fronted by CloudFront (which also serves a tiny static site with a link-quality
test). Designed to be shared with a handful of friends and family, not the
public internet.

## What you get after `terraform apply`

- `https://<dist>.cloudfront.net/` — static page with a **Run test** button
  that measures latency and download throughput against the edge.
- A `vmess://…` share link printed via `terraform output` and written to
  `v2ray-share.txt` — paste into v2rayN / v2rayNG / Shadowrocket / any v2ray
  client.
- A full `client-config.json` for headless use.

## Prerequisites

- AWS credentials with permission to create EC2 / VPC subnet / S3 /
  CloudFront. The current setup expects them under an `AWS_PROFILE=personal`
  named profile.
- Terraform `1.5.1` (pinned in `.tool-versions`).
- The deploy region is hard-coded to `eu-central-1` (Frankfurt).

## Deploy

```bash
cd terraform
terraform init                                          # one-time
AWS_PROFILE=personal terraform plan                     # diff preview
AWS_PROFILE=personal terraform apply                    # creates EC2 + S3 + CloudFront
AWS_PROFILE=personal terraform output -raw vmess_share_link
```

`apply` takes ~3–5 min total (most of it is CloudFront creation). After it
returns, the share link is also written to `v2ray-share.txt` at the repo root,
and a full `client-config.json` is written next to it (both git-ignored).

The CloudFront distribution may take an additional minute or two to fully
propagate to all edges after the apply finishes. If `/ping` returns 504
immediately after apply, just wait a moment and retry.

## Rotate credentials

The VMess UUID in the share link is the only credential. To rotate (e.g. after
sharing with someone you'd rather un-share with):

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
cd terraform
AWS_PROFILE=personal terraform destroy
```

`destroy` is the canonical "stop charging me" — it removes the EC2 instance,
EBS volume, S3 bucket (and the `index.html` inside), CloudFront distribution
(slowest step — disabling a distribution takes ~3 min), and the public
subnet. Note that the AWS account still exists; this only tears down what
Terraform created.

## Cost (rough, idle)

- EC2 `t3.small`: ~$15/mo
- EBS 8 GB gp3: ~$0.70/mo
- CloudFront: free tier covers 1 TB/mo egress + 10M requests
  (`PriceClass_All` ≈ +15% per GB vs. `PriceClass_100`)
- S3: pennies

## Interpreting the speed-test page

`/ping` is a small, uncached round trip to EC2 — gives you **latency**.
`/speedtest` is a 5 MB random payload served by EC2 with caching disabled
all the way through CloudFront — gives you **throughput**.

Because both bypass the CloudFront cache, the numbers reflect the path your
v2ray traffic actually takes (`client → CloudFront edge → EC2 in Frankfurt`).
If the page shows ~30 Mbps and a few hundred ms latency, that's roughly what
v2ray will give you. If it shows < 1 Mbps and multi-second latency, your ISP
is throttling AWS or you're being routed through a distant edge — that's a
network condition, not a stack problem. Retry at a different time or from a
different network.

Tunables in `terraform/variables.tf`:

| Variable | Default | What it controls |
|---|---|---|
| `instance_type` | `t3.small` | EC2 size. `t3.micro` is cheaper; `c6i.large` if you need real bandwidth. |
| `ws_path` | `/stream` | URL path v2ray's WebSocket lives at. |
| `speedtest_mb` | `5` | Size of the random payload served at `/speedtest`. |

## See also

- [ARCHITECTURE.md](./ARCHITECTURE.md) — diagram and rationale for the
  CloudFront-in-front-of-EC2 layout.
- [CLAUDE.md](./CLAUDE.md) — notes for any future Claude session working in
  this repo.
