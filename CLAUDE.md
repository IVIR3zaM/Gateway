# CLAUDE.md

Notes for any future Claude session working in this repo.

## What this project is

A minimal personal v2ray gateway on AWS — one EC2 instance in `eu-central-1`
(Frankfurt) plus a CloudFront distribution that serves both a tiny static site
(an S3 bucket with `index.html`) and the v2ray WebSocket endpoint. See
[ARCHITECTURE.md](./ARCHITECTURE.md) for the diagram.

## Repo layout

```
terraform/        Single root module. Default provider is eu-central-1.
  providers.tf    Provider block + version pins.
  variables.tf    Tunables (name prefix, instance type, ws_path, speedtest_mb).
  ec2.tf          AMI lookup, security group, instance, user-data templating.
  s3.tf           Private bucket + OAC-scoped policy + index.html upload.
  cloudfront.tf   Distribution with S3 + EC2 origins, per-path behaviors.
  outputs.tf      vmess:// share link, client-config.json, CloudFront domain.
  templates/      .tftpl files rendered into user-data.
site/             Static site (index.html). Uploaded as-is to S3.
```

## Things to know before changing code

- **No default AWS provider alias.** The `aws` provider is plain `eu-central-1`.
  If you ever need a us-east-1 ACM cert for CloudFront, add a `provider "aws"
  { alias = "useast1" region = "us-east-1" }` block and set `provider =
  aws.useast1` on those resources only.

- **CloudFront cache policy IDs are AWS-managed UUIDs**, hard-coded in
  `cloudfront.tf`:
  - `658327ea-…` — CachingOptimized (default behavior, S3 origin).
  - `4135ea2d-…` — CachingDisabled (all EC2 behaviors).
  - `216adef6-…` — AllViewer origin request policy.
  Don't replace these with custom policies unless there's a real reason.

- **The VMess UUID is the only credential.** It lives in
  `random_uuid.vmess_id` and is baked into both the server config (via
  `user_data`) and the client share link. Rotating it requires both an EC2
  replacement (user_data change → instance replacement) and a CloudFront
  invalidation isn't needed.

- **`var.ws_path` is the WebSocket path.** It's referenced from three places:
  the nginx config, the v2ray server config, and the CloudFront ordered
  behavior. Change in one place and the others will follow because they're
  all driven from the variable.

- **EC2 security group allows public :80.** Tightening to the
  `com.amazonaws.global.cloudfront.origin-facing` managed prefix list is the
  obvious next hardening step but is left out for now to keep the stack small.

- **`v2ray-share.txt` and `client-config.json` are generated outputs** and
  live at the repo root after `terraform apply`. They're in `.gitignore`.

## How to verify a change

1. `cd terraform && terraform fmt && terraform validate`
2. `terraform plan` — diff should be empty for cosmetic changes.
3. For changes that touch user-data, expect EC2 to be replaced
   (`# forces replacement`). That's a ~2-minute outage and a new public IP
   (CloudFront keeps the same domain because the origin is the EC2 public DNS,
   which also changes — so CloudFront origin will re-point on apply).

## Don't

- Don't add a real domain or ACM cert unless the user asks; the whole point of
  this stack is "no domain required."
- Don't move state to S3/remote backend without asking — local state is fine
  for a single-operator hobby project.
- Don't bake additional VMess clients into the config silently; that's a
  product decision, not a tidy-up.
