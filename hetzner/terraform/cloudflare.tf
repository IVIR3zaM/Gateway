data "cloudflare_zones" "this" {
  filter {
    name = var.domain
  }
}

locals {
  zone_id = data.cloudflare_zones.this.zones[0].id
}

# Proxied A record (orange cloud) — this is what makes Iranian ISPs see
# Cloudflare IPs instead of Hetzner's. AAAA optional; v2ray clients on mobile
# can be flaky with IPv6, so we leave it as A-only for now.
resource "cloudflare_record" "gw" {
  zone_id = local.zone_id
  name    = var.subdomain
  type    = "A"
  content = hcloud_server.v2ray.ipv4_address
  proxied = true
  ttl     = 1 # "Auto" — required when proxied
  comment = "Gateway v2ray endpoint — managed by terraform"
}

# Force Full SSL + websockets at the zone level so the gateway works regardless
# of dashboard state. Note: these settings apply to the whole zone — if you
# host anything else on the apex, make sure it already serves HTTPS.
resource "cloudflare_zone_settings_override" "this" {
  zone_id = local.zone_id

  settings {
    ssl                      = "full"
    always_use_https         = "on"
    min_tls_version          = "1.2"
    websockets               = "on"
    automatic_https_rewrites = "on"
    opportunistic_encryption = "on"
    tls_1_3                  = "on"
  }
}
