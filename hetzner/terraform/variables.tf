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
  description = "OPTIONAL SSH public key (full line, e.g. 'ssh-ed25519 AAA... user@host'). Set to null to skip; you lose console-less recovery if you do."
  type        = string
  default     = null
}

variable "ssh_allow_cidrs" {
  description = "CIDRs allowed to reach :22. Default is empty (SSH closed). Add your home IP/32 if you want shell access."
  type        = list(string)
  default     = []
}

variable "debug_allow_cidrs" {
  description = "EXTRA source CIDRs allowed to reach :443 directly (bypassing Cloudflare). Leave empty in production; use only to test the origin during incident response."
  type        = list(string)
  default     = []
}

variable "geoip_mmdb_url" {
  description = "OPTIONAL direct URL to a country MMDB (.mmdb or .mmdb.gz). When set, user-data downloads it at boot and the stats collector uses it for IP→country lookups (offline, instant). When unset, the collector falls back to ip-api.com (rate-limited, sometimes shows white flags). Sources: see hetzner/README.md."
  type        = string
  default     = null
  sensitive   = true
}
