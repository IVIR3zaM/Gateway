variable "name" {
  description = "Resource name prefix."
  type        = string
  default     = "gateway"
}

variable "region" {
  description = "AWS region the EC2 origin lives in. CloudFront is global; the distribution and vmess share link don't change when this changes."
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "EC2 instance type for the v2ray server."
  type        = string
  default     = "t3.small"
}

variable "ws_path" {
  description = "WebSocket path that v2ray listens on behind CloudFront."
  type        = string
  default     = "/stream"
}

variable "speedtest_mb" {
  description = "Size (MB) of the random payload served at /speedtest."
  type        = number
  default     = 5
}
