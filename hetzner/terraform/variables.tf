variable "name" {
  description = "Resource name prefix."
  type        = string
  default     = "gateway"
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token. Read+write. Export as TF_VAR_hcloud_token."
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token. Needs Zone:DNS:Edit + Zone:Zone Settings:Edit + Zone:Zone:Read on the target zone. Export as TF_VAR_cloudflare_api_token."
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "Apex domain registered in Cloudflare, e.g. example.com."
  type        = string
}

variable "subdomain" {
  description = "Subdomain (label only) the gateway is served from. Final hostname is <subdomain>.<domain>."
  type        = string
  default     = "gw"
}

variable "location" {
  description = "Hetzner Cloud datacenter location: fsn1 (Falkenstein), hel1 (Helsinki), nbg1 (Nuremberg)."
  type        = string
  default     = "fsn1"
}

variable "server_type" {
  description = "Hetzner server type. cx23 = 2 vCPU Intel / 4GB / x86 (current gen). cpx11 = 2 vCPU AMD / 2GB (cheaper). cax11 = 2 vCPU ARM / 4GB."
  type        = string
  default     = "cx23"
}

variable "image" {
  description = "Hetzner image slug."
  type        = string
  default     = "debian-12"
}

variable "ws_path" {
  description = "WebSocket path that v2ray listens on behind Cloudflare."
  type        = string
  default     = "/stream"
}

variable "speedtest_mb" {
  description = "Size (MB) of the random payload served at /speedtest."
  type        = number
  default     = 5
}

variable "ssh_public_key" {
  description = "Override for the operator SSH public key. Default: read from ~/.ssh/id_ed25519.pub at plan time."
  type        = string
  default     = null
}

variable "ssh_private_key_path" {
  description = "Override path to the matching SSH private key (used by the blue/green readiness gate). Default: ~/.ssh/id_ed25519."
  type        = string
  default     = null
}

variable "ssh_allow_cidrs" {
  description = "Override CIDRs allowed to reach :22. Default: auto-detected operator public IP (see local_env.tf). Set explicitly if running from CI or want to pin a static range."
  type        = list(string)
  default     = []
}

variable "debug_allow_cidrs" {
  description = "EXTRA source CIDRs allowed to reach :443 directly (bypassing Cloudflare). Leave empty in production; use only to test the origin during incident response."
  type        = list(string)
  default     = []
}
