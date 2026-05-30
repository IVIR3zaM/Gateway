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
4. Terraform ≥ 1.5.

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

Optionally set `ssh_public_key` and `ssh_allow_cidrs` if you want a shell
on the VM. Default is no SSH at all — the box is fully managed by user-data.

`terraform.tfvars` is gitignored.

---

## Step 4 — Apply

```bash
cd hetzner/terraform
terraform init
terraform plan
terraform apply
```

Expect:

- 1 × `hcloud_server`
- 1 × `hcloud_firewall`
- 0–1 × `hcloud_ssh_key` (only if you set `ssh_public_key`)
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
