output "server_ipv4" {
  description = "Hetzner public IPv4. Cloudflare A record points here."
  value       = hcloud_server.v2ray.ipv4_address
}

output "fqdn" {
  description = "Public hostname for the static site, /speedtest, /stats.json, and v2ray WS."
  value       = local.fqdn
}

output "site_url" {
  value = "https://${local.fqdn}/"
}

output "vmess_uuid" {
  value     = random_uuid.vmess_id.result
  sensitive = true
}

locals {
  vmess_share_json = jsonencode({
    v    = "2"
    ps   = "${var.name}-hetzner-${var.location}"
    add  = local.fqdn
    port = "443"
    id   = random_uuid.vmess_id.result
    aid  = "0"
    scy  = "auto"
    net  = "ws"
    type = "none"
    host = local.fqdn
    path = var.ws_path
    tls  = "tls"
    sni  = local.fqdn
  })

  vmess_share_link = "vmess://${base64encode(local.vmess_share_json)}"

  client_config = {
    inbounds = [{
      port     = 1080
      listen   = "127.0.0.1"
      protocol = "socks"
      settings = { udp = true }
    }]
    outbounds = [{
      protocol = "vmess"
      settings = {
        vnext = [{
          address = local.fqdn
          port    = 443
          users   = [{ id = random_uuid.vmess_id.result, alterId = 0, security = "auto" }]
        }]
      }
      streamSettings = {
        network  = "ws"
        security = "tls"
        wsSettings = {
          path    = var.ws_path
          headers = { Host = local.fqdn }
        }
        tlsSettings = { serverName = local.fqdn }
      }
    }]
  }
}

resource "local_file" "vmess_share" {
  filename = "${path.module}/../v2ray-share.txt"
  content  = "${local.vmess_share_link}\n"
}

resource "local_file" "client_config" {
  filename = "${path.module}/../client-config.json"
  content  = jsonencode(local.client_config)
}

output "vmess_share_link" {
  description = "vmess:// link — paste into v2rayN, v2rayNG, Shadowrocket, etc."
  value       = local.vmess_share_link
  sensitive   = true
}
