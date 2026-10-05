# Hetzner + Cloudflare gateway

Parallel implementation of the AWS stack, designed for users in Iran where
AWS IP ranges are routinely blocked. Same vmess link shape, same landing page,
same `/speedtest` and `/stats.json` — different boxes underneath:

```
client → Cloudflare (proxied) → Hetzner Cloud VM (nginx + v2ray, fsn1)
```

The Hetzner firewall locks the VM's :443 to Cloudflare's published IP ranges,
so the only way in is through Cloudflare.

## What you need before `terraform apply`

1. A Hetzner Cloud **project** and an **API token** (read+write).
2. A Cloudflare account with `example.com` as an active zone.
3. A Cloudflare **API token** scoped to that zone.
4. Terraform 1.16.5, the version pinned in the root `.tool-versions` (at
   least 1.10, which the R2 backend's lock file needs). A state written by
   1.16 is unreadable by 1.5, so don't apply with an older binary.
5. A Cloudflare R2 bucket and R2 API token for the Terraform state (see
   **State backend (Cloudflare R2)**).

Steps 1–3 are below.

---

## Step 1 — Create a Hetzner Cloud project + API token

Hetzner has *two* products with confusingly similar names:

- **Hetzner Cloud** (`console.hetzner.cloud`) — pay-per-hour VMs, has an API,
  Terraform-friendly. **This is what we want.**
- **Hetzner Robot** (`robot.hetzner.com`) — bare-metal dedicated servers,
  monthly billing, different API. Not this.

If you happen to have other Hetzner products tied to the same account
(shared Web Hosting / KonsoleH, dedicated Robot servers), they're untouched
by anything here — different product, different control plane.

1. Open <https://console.hetzner.cloud/> and log in with the same account
   that owns the domain.
2. Click **New Project**, name it `gateway`. (Or reuse an existing project —
   the resources will be tagged `project=gateway` either way.)
3. Inside the project, sidebar → **Security** → **API Tokens** → **Generate API token**.
4. Description: `terraform gateway`. Permissions: **Read & Write**. Click
   **Generate**.
5. **Copy the token immediately** — it's shown exactly once. Format:
   `hcloud_abc123…` (64 chars).

Stash it somewhere you can paste from in step 4.

---

## Step 2 — Get the apex domain onto Cloudflare

The gateway lives on a subdomain (`gw.<your-domain>` by default), but the
**whole zone** needs to be on Cloudflare so Terraform can create that record
and apply zone-level SSL settings. Cloudflare Free doesn't support managing
just a subdomain — that's a paid (Business+) feature called Subdomain Setup.

If your zone is already on Cloudflare, skip to **2c**.

If your zone is somewhere else (your registrar's DNS, Hetzner DNS, another
host's nameservers), the migration is safe as long as you mirror any existing
records into Cloudflare before flipping nameservers — Cloudflare's setup
wizard does this for you automatically.

### 2a. Add the zone

1. Sign up / log in at <https://dash.cloudflare.com>.
2. **Add a site** → enter your apex (`example.com`). Pick the **Free** plan.
3. Cloudflare scans existing DNS and shows the records it found.
   - **Review the import carefully** — every record you currently serve
     (apex `A`/`AAAA`, `www`, `MX`, `TXT`, mail subdomains, etc.) should be
     there. If anything is missing, add it before continuing.
   - Leave the **proxy status as DNS-only (gray cloud)** for any record
     that points at an external host (mail server, existing website on
     another provider, etc.). Only orange-cloud records you intentionally
     want Cloudflare to proxy.
   - Don't add a `gw` record manually — Terraform creates it in Step 4.
4. Click **Continue** through the import.

### 2b. Switch nameservers at your registrar

Cloudflare shows you two nameservers, e.g. `aria.ns.cloudflare.com` and
`pablo.ns.cloudflare.com`. Replace your current NS records with that pair at
whichever registrar holds the domain (Namecheap, GoDaddy, Hetzner Domain
Registration, etc.).

Propagation: typically 5–30 min, up to 24h worst case. During the cutover
both old and new nameservers continue to answer with the same records (since
you mirrored them in 2a), so existing sites stay up.

When Cloudflare's dashboard shows the zone status as **Active**, you're done
with step 2.

### 2c. Create the Cloudflare API token

1. Dashboard → top-right profile → **My Profile** → **API Tokens** →
   **Create Token**.
2. Use the **Custom token** template (not the "Edit zone DNS" preset —
   we need slightly more than DNS).
3. Permissions (add three rows):
   - `Zone` · `Zone` · `Read`
   - `Zone` · `DNS` · `Edit`
   - `Zone` · `Zone Settings` · `Edit`
4. Zone Resources: **Include** → **Specific zone** → `example.com`.
5. Continue, create, **copy the token immediately**. Format: 40-ish opaque
   chars.

---

## Step 3 — Fill in tfvars

```bash
cd hetzner/terraform
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
```

Set at minimum:

- `domain               = "example.com"`
- `subdomain            = "gw"` (so the gateway is `gw.example.com`)
- `hcloud_token         = "hcloud_…"`
- `cloudflare_api_token = "…"`

SSH is always on: the readiness gate in `readiness.tf` uses it to wait for
the new VM before the DNS record moves. Port 22 opens only to your public
IP, auto-detected at every plan; set `ssh_allow_cidrs` to pin a range
instead. The key comes from `~/.ssh/id_rsa.pub` (and `~/.ssh/id_rsa` for the
gate) unless you set `ssh_public_key` and `ssh_private_key_path`.

`terraform.tfvars` is gitignored.

---

## State backend (Cloudflare R2)

Gateway, Sonar and Kita share one private R2 bucket and one R2 API token
(Object Read & Write on that bucket). Each project has its own key;
Gateway's is `gateway/terraform.tfstate` (set in `providers.tf`). Terraform
locks the state with a lock file next to it in the bucket, so a local run
and a CI run never apply at the same time.

1. In Cloudflare, create the private bucket once (or reuse the one Sonar or
   Kita already uses) and an R2 API token scoped to it. Note the account ID,
   the bucket name, and the token's access key ID and secret access key.
2. Create the backend config (gitignored) and fill in the bucket, account ID,
   and the token's two keys:

   ```bash
   cd hetzner/terraform
   cp backend.hcl.example backend.hcl
   chmod 600 backend.hcl
   ```

   Edit `backend.hcl` and replace the placeholders for `access_key`,
   `secret_key`, `bucket` and `endpoints`.

3. The R2 credentials in `backend.hcl` take precedence over any AWS_ACCESS_KEY_ID,
   AWS_SECRET_ACCESS_KEY, AWS_PROFILE in the shell or `~/.aws`, so nothing is
   exported and other AWS profiles and `~/.aws` stay untouched. A root initialized
   before the keys were added is re-initialized once with:

   ```bash
   terraform init -reconfigure -backend-config=backend.hcl
   ```

   `backend.hcl` is gitignored and holds the R2 keys. Terraform keeps a copy
   in the gitignored `.terraform/` directory and in any saved `-out` plan file,
   so never share `backend.hcl`, `.terraform/` or `-out` files outside your
   machine.

4. One time only, if you already have a local `terraform.tfstate` from an
   earlier apply, move it into R2:

   ```bash
   terraform init -migrate-state -backend-config=backend.hcl
   ```

   Answer yes to copy the state. Afterwards `terraform state list` must show
   the server, the firewall, the DNS record and the rest of the stack; then
   keep the old local state files only as a private backup. On a first-ever
   apply there is nothing to migrate: Step 4's `init` is enough.

---

## Step 4 — Apply

```bash
cd hetzner/terraform
terraform init -backend-config=backend.hcl
terraform plan -lock-timeout=10m
terraform apply -lock-timeout=10m
```

With `backend.hcl` filled in (see above). `-lock-timeout=10m` makes a
local run wait for a CI run that holds the lock, instead of failing.

Expect:

- 1 × `hcloud_server`
- 1 × `hcloud_firewall`
- 1 × `hcloud_ssh_key`
- 1 × `cloudflare_record` (the `gw` A record)
- 1 × `cloudflare_zone_settings_override` (zone-wide SSL + websockets)
- a self-signed cert and key (TLS materials, not visible in CF/Hetzner)
- 2 × `local_file` — `../v2ray-share.txt` and `../client-config.json`

Apply takes ~30s for the API calls; the VM then runs cloud-init for ~60–90s
before nginx and v2ray are ready. Watch:

```bash
curl -fsS https://gw.example.com/ping   # should print "ok"
curl -fsS https://gw.example.com/        # static landing page
```

The `vmess://` link is in `hetzner/v2ray-share.txt`. Paste it into v2rayN /
v2rayNG / Shadowrocket / etc.

---

## GitHub Actions

`.github/workflows/hetzner.yml` (workflow `Hetzner`) has two jobs:

- `validate` runs `terraform fmt -check -recursive`, `terraform init
  -backend=false` and `terraform validate` in `hetzner/terraform`. It uses
  no environment and no secret.
- `apply` needs `validate` and runs in the `production` environment. It
  plans and applies `hetzner/terraform` on the R2 backend, then redeploys
  Sonar and Kita if the VM was replaced.

Both jobs install the Terraform version from the root `.tool-versions`.

What triggers a run:

- **Push to main** that touches `hetzner/**`, `.tool-versions` or the
  workflow file: validate, plan and apply.
- **Dispatch:** Actions, Hetzner, Run workflow. Input `replace_server`
  (default false) adds `-replace=random_id.server_suffix
  -replace=hcloud_server.v2ray` to the plan, so the VM is rebuilt even when
  nothing changed. It is the recovery tool for a broken VM and the way to
  force a replacement. From the command line:

  ```bash
  gh workflow run hetzner.yml                        # plan and apply main
  gh workflow run hetzner.yml -f replace_server=true # rebuild the VM
  ```

Set up once, in the repository settings:

1. Create the environment `production` and limit its deployment branches to
   `main`. The `apply` job runs in it.
2. Add these secrets and variables to the `production` environment:

   | Name | Kind | Terraform variable or use |
   |---|---|---|
   | `HCLOUD_TOKEN` | secret | `hcloud_token` |
   | `CLOUDFLARE_API_TOKEN` | secret | `cloudflare_api_token` |
   | `DOMAIN` | secret | `domain`, for example `example.com` |
   | `SUBDOMAIN` | secret | `subdomain`, for example `gw` for `gw.example.com` |
   | `WS_PATH` | secret | `ws_path` |
   | `SSH_PRIVATE_KEY` | secret | written to a mode-600 file in the runner's temp dir; its path is `ssh_private_key_path` |
   | `SSH_PUBLIC_KEY` | variable | `ssh_public_key`; must equal the key in the state, or the VM is replaced |
   | `DISPATCH_TOKEN` | secret | `GH_TOKEN` for dispatching the Sonar and Kita deploys (see **App redeploys**) |
   | `R2_ACCESS_KEY_ID` | secret | `AWS_ACCESS_KEY_ID` for the R2 backend |
   | `R2_SECRET_ACCESS_KEY` | secret | `AWS_SECRET_ACCESS_KEY` for the R2 backend |
   | `R2_ACCOUNT_ID` | variable | endpoint `https://<account-id>.r2.cloudflarestorage.com` in the generated `backend.hcl` |
   | `R2_BUCKET` | variable | `bucket` in the generated `backend.hcl` |
   | `NAME` | variable, optional | `name` |
   | `LOCATION` | variable, optional | `location` |
   | `SERVER_TYPE` | variable, optional | `server_type` |
   | `IMAGE` | variable, optional | `image` |
   | `SPEEDTEST_MB` | variable, optional | `speedtest_mb` |

   Every non-optional name must be set: the job fails before terraform runs
   and names the empty one (an empty `SUBDOMAIN` would put the A record on
   the apex). An optional variable left unset keeps the Terraform default.
   `ssh_allow_cidrs` is not set in CI, so port 22 opens to the runner's own
   IPv4 for that run.

How the apply job behaves:

- **One at a time:** every run joins the `deploy` concurrency queue and
  waits; none is cancelled, because an apply cut short could leave the R2
  lock held.
- **Empty-state guard:** after `terraform init` the job checks `terraform
  state list`. If the state is empty (not migrated to R2, or the wrong bucket
  or key) it fails before planning, because an apply would create a second
  VM and DNS record.
- **Lock:** plan and apply run with `-lock-timeout=10m`, so they wait for a
  local run that holds the lock.
- **Logs are public.** The repository is public, so anyone can read the
  workflow logs. The full plan stays on the runner; the log shows only each
  changed resource's address and actions. The apply log, and a failed
  plan's output, have every IPv4 replaced by `x.x.x.x` and every resource
  id replaced by `[id=x]`. Terraform outputs are never printed: the apply
  log drops its closing `Outputs:` block, and the job reads only `server_id`, into a file on the runner, and passes on nothing
  but whether it changed. Read outputs such as the share link from your
  machine instead.
- **Generated files:** the two `local_file` artifacts (`v2ray-share.txt`
  and `client-config.json`) are re-created on the runner at every run and
  never leave it. Run terraform locally to get them.

### App redeploys

A new VM has neither Sonar nor Kita installed. The job records the
`server_id` output before the plan and compares it after the apply; when it
changed, or was unknown before, it dispatches both apps' `ci.yml` with
`ref=main`, which reinstalls them on the new VM. A redundant dispatch only
redeploys the same commit.

`DISPATCH_TOKEN` is a fine-grained personal access token limited to the
repositories Sonar and Kita, with **Actions: Read and write** and nothing
else. Give it an expiry and renew it before it lapses; an expired token
fails the dispatch step after a successful apply, and you then run
`gh workflow run ci.yml -f ref=main` in each app's repository.

---

## Coexistence with Sonar and Kita

Sonar and Kita run on the same VM and keep their own state in the same R2
bucket.

- **Firewalls:** Sonar and Kita attach their own `sonar-ssh` and `kita-ssh`
  firewalls to the server by label `project=gateway`.
  `ignore_remote_firewall_ids` on `hcloud_server.v2ray` keeps a Gateway
  apply from detaching them.
- **Replacement window:** during a VM replacement two servers briefly carry
  `project=gateway`. An app deploy in that window fails its
  exactly-one-server check before changing anything; re-run it once the old
  server is gone (the dispatch after the apply already runs after that).
- **nginx:** the apps install `conf.d/sonar.conf` and `conf.d/kita.conf`,
  which Gateway's `nginx.conf` includes. Together they must pass `nginx -t`;
  keep server names and listen options compatible across the three projects
  when changing the nginx config here.
- **Lock:** local and CI runs of all three projects use the same bucket, and
  runs on the same state queue on its R2 lock (up to `-lock-timeout=10m`).

---

## Country flags

The landing page shows one flag per distinct country currently connected.
The country comes from Cloudflare's `CF-IPCountry` header (logged by nginx
on every WS handshake), so there's no IP→country lookup, no third-party
service, and no client IPs stored on disk. One real user = one flag, even
if their mobile carrier rotates the source IP between reconnects.

## Choosing a server size

`server_type` in `terraform.tfvars` controls the VM size. Changing it forces
a VM rebuild but **does not change the VMess link** — the UUID, FQDN, and
WS path stay the same. Apply takes ~90s; Cloudflare's A record is updated
automatically, so clients reconnect without re-importing the share link.

Current sizes available in `fsn1` (Falkenstein) — server price only; add
**€0.60/mo for the primary IPv4** and **€20/TB** for traffic over the
included 20 TB. Live prices: `GET https://api.hetzner.cloud/v1/server_types`.

**Shared-CPU x86 (Intel) — default tier.** Cheapest. Default is `cx23`.

| name   | vCPU | RAM   | disk   | €/mo  |
|--------|-----:|------:|-------:|------:|
| cx23   | 2    | 4 GB  | 40 GB  | 4.95  |
| cx33   | 4    | 8 GB  | 80 GB  | 8.05  |
| cx43   | 8    | 16 GB | 160 GB | 14.87 |
| cx53   | 16   | 32 GB | 320 GB | 27.89 |

**Shared-CPU x86 (AMD).** Same shape, AMD silicon, usually a bit pricier.

| name   | vCPU | RAM   | disk   | €/mo  |
|--------|-----:|------:|-------:|------:|
| cpx11  | 2    | 2 GB  | 40 GB  | 6.81  |
| cpx21  | 3    | 4 GB  | 80 GB  | 11.77 |
| cpx31  | 4    | 8 GB  | 160 GB | 21.69 |
| cpx41  | 8    | 16 GB | 240 GB | 40.29 |
| cpx51  | 16   | 32 GB | 360 GB | 88.03 |

**Shared-CPU ARM (Ampere).** Cheapest cores at a given RAM tier. Image
must be ARM-compatible — `debian-12` works.

| name   | vCPU | RAM   | disk   | €/mo  |
|--------|-----:|------:|-------:|------:|
| cax11  | 2    | 4 GB  | 40 GB  | 5.57  |
| cax21  | 4    | 8 GB  | 80 GB  | 9.91  |
| cax31  | 8    | 16 GB | 160 GB | 19.83 |
| cax41  | 16   | 32 GB | 320 GB | 39.05 |

**Dedicated-CPU x86 (`ccx*`).** Guaranteed cores, no noisy-neighbour. Only
worth it if a shared SKU stops keeping up — for one-person v2ray traffic
through a 1 Gbps NIC that's effectively never. Prices start at €19.83/mo
(`ccx13`, 2 vCPU / 8 GB) and go up; check the API for the full list.

For a personal gateway with one or two clients, **`cx23` is plenty** — v2ray
+ nginx + the stats collector idle at ~1% CPU and ~100 MB RAM. Upgrade only
if `/stats.json` shows sustained high CPU or you push close to 1 Gbps.

## Operational notes

- **Rotating the VMess UUID**: `terraform taint random_uuid.vmess_id && terraform apply`.
  That replaces the VM (~90s of downtime) and overwrites the share files.
- **Resizing the VM**: edit `server_type` and `terraform apply`. Same
  ~90s outage, same VMess link, no client changes needed. See
  **Choosing a server size** above for the catalog.
- **Changing user-data**: forces VM replacement, same as the AWS stack. The
  public IP changes too — Terraform updates the Cloudflare A record in the
  same apply, so clients reconnect automatically once propagation catches up
  (~30s through Cloudflare).
- **Cost**: default `cx23` in fsn1 is ~€4.95/mo + €0.60/mo for the IPv4.
  Cloudflare Free plan = €0. No CloudFront / S3 charges.
- **Cloudflare ToS reminder**: §2.8 forbids tunneling non-HTML traffic over
  the free plan. Personal-scale v2ray-in-WS-in-TLS is indistinguishable from
  normal HTTPS in practice, but it's a real risk for heavy users. If you
  push tens of GB/day through it, expect attention.

## Troubleshooting

- **`502 Bad Gateway` from Cloudflare**: origin is up but Cloudflare can't
  reach it. Usually: the firewall rule lost sync because Cloudflare changed
  its IP ranges. `terraform apply` re-fetches them.
- **`525 SSL handshake failed`**: origin cert is missing or expired.
  Re-apply; the cert is generated by Terraform and lives in state.
- **Site works, vmess doesn't**: check `ws_path` matches between
  `terraform.tfvars` and your client config. Both default to `/stream`.
- **No flags but connections work**: nginx isn't seeing `CF-IPCountry`.
  Either Cloudflare proxying is off for the subdomain (orange-cloud must be
  on) or the request is bypassing CF entirely (check the Hetzner firewall
  still restricts :443 to Cloudflare IPs).
