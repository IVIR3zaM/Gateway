resource "random_uuid" "vmess_id" {}

# Optional self-signed cert pair for nginx :443. Cloudflare runs in "Full" (not
# Strict) SSL mode, so it doesn't validate the chain — but CF↔origin traffic is
# still encrypted, and the origin is firewalled to Cloudflare IPs anyway.
resource "tls_private_key" "origin" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "origin" {
  private_key_pem = tls_private_key.origin.private_key_pem

  subject {
    common_name = local.fqdn
  }

  dns_names = [local.fqdn]

  validity_period_hours = 24 * 365 * 10
  early_renewal_hours   = 24 * 30

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

locals {
  fqdn = "${var.subdomain}.${var.domain}"

  v2ray_server_config = templatefile("${path.module}/templates/v2ray-server.json.tftpl", {
    uuid    = random_uuid.vmess_id.result
    ws_path = var.ws_path
  })

  nginx_config = templatefile("${path.module}/templates/nginx.conf.tftpl", {
    ws_path = var.ws_path
    fqdn    = local.fqdn
  })

  # Hetzner Cloud VMs share 1 Gbps egress. Used only as a reference line in
  # the stats panel — not a hard quota.
  stats_script = templatefile("${path.module}/templates/stats.sh.tftpl", {
    baseline_mbps = 1000
  })

  site_index_html = file("${path.module}/../site/index.html")

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    v2ray_config    = local.v2ray_server_config
    nginx_config    = local.nginx_config
    speedtest_mb    = var.speedtest_mb
    stats_script    = local.stats_script
    site_index_html = local.site_index_html
    origin_cert_pem = tls_self_signed_cert.origin.cert_pem
    origin_key_pem  = tls_private_key.origin.private_key_pem
  })
}

resource "hcloud_ssh_key" "this" {
  count      = var.ssh_public_key == null ? 0 : 1
  name       = "${var.name}-key"
  public_key = var.ssh_public_key
}

resource "hcloud_server" "v2ray" {
  name         = "${var.name}-v2ray"
  server_type  = var.server_type
  image        = var.image
  location     = var.location
  user_data    = local.user_data
  ssh_keys     = var.ssh_public_key == null ? [] : [hcloud_ssh_key.this[0].id]
  firewall_ids = [hcloud_firewall.v2ray.id]

  labels = {
    project    = "gateway"
    managed-by = "terraform"
  }
}
