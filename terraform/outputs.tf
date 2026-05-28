output "cloudfront_domain" {
  description = "Public hostname for the static site, speed test, and v2ray WS."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "site_url" {
  value = "https://${aws_cloudfront_distribution.this.domain_name}/"
}

output "ec2_public_dns" {
  description = "EC2 public DNS (CloudFront origin only — not for end users)."
  value       = aws_instance.v2ray.public_dns
}

output "vmess_uuid" {
  value     = random_uuid.vmess_id.result
  sensitive = true
}

locals {
  # vmess:// share URL — base64(JSON of standard v2rayN spec).
  vmess_share_json = jsonencode({
    v    = "2"
    ps   = "${var.name}-frankfurt"
    add  = aws_cloudfront_distribution.this.domain_name
    port = "443"
    id   = random_uuid.vmess_id.result
    aid  = "0"
    scy  = "auto"
    net  = "ws"
    type = "none"
    host = aws_cloudfront_distribution.this.domain_name
    path = var.ws_path
    tls  = "tls"
    sni  = aws_cloudfront_distribution.this.domain_name
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
          address = aws_cloudfront_distribution.this.domain_name
          port    = 443
          users   = [{ id = random_uuid.vmess_id.result, alterId = 0, security = "auto" }]
        }]
      }
      streamSettings = {
        network  = "ws"
        security = "tls"
        wsSettings = {
          path    = var.ws_path
          headers = { Host = aws_cloudfront_distribution.this.domain_name }
        }
        tlsSettings = { serverName = aws_cloudfront_distribution.this.domain_name }
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
