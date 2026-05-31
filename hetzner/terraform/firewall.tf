# Cloudflare's published proxy IP ranges. Used to lock :443 to CF only.
data "cloudflare_ip_ranges" "cf" {}

resource "hcloud_firewall" "v2ray" {
  name = "${var.name}-v2ray"

  # 443 from Cloudflare + any operator debug CIDRs.
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = concat(
      data.cloudflare_ip_ranges.cf.ipv4_cidr_blocks,
      data.cloudflare_ip_ranges.cf.ipv6_cidr_blocks,
      var.debug_allow_cidrs,
    )
    description = "HTTPS from Cloudflare (+ debug CIDRs if set)"
  }

  # 80 also Cloudflare-only — nginx redirects to 443. Lets Cloudflare's
  # "Always Use HTTPS" work even when a client somehow hits port 80.
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = concat(
      data.cloudflare_ip_ranges.cf.ipv4_cidr_blocks,
      data.cloudflare_ip_ranges.cf.ipv6_cidr_blocks,
    )
    description = "HTTP from Cloudflare (redirected to HTTPS)"
  }

  # SSH defaults to the operator's auto-detected public IP (see local_env.tf);
  # override with var.ssh_allow_cidrs to pin specific CIDRs (e.g. from CI).
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = local.effective_ssh_allow_cidrs
    description = "SSH from operator CIDRs"
  }

  # ICMP — useful for debugging from anywhere, harmless.
  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "ICMP"
  }
}
