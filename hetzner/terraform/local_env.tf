# Operator auto-detection. Every `terraform plan` re-fetches the public IP and
# re-reads the local SSH key, so a roaming laptop doesn't need to keep editing
# tfvars. All three are overridable via the matching variables; the key file is
# read only when var.ssh_public_key is unset.

data "http" "my_ip_primary" {
  url = "https://api.ipify.org"
  retry {
    attempts = 2
  }
}

# Fallback service in case ipify is down — plan would otherwise hard-fail. The
# ipv4. host never answers with an IPv6 address, which would break the /32 CIDR.
data "http" "my_ip_fallback" {
  url = "https://ipv4.icanhazip.com"
  retry {
    attempts = 2
  }
}

locals {
  detected_ip = try(
    chomp(data.http.my_ip_primary.response_body),
    chomp(data.http.my_ip_fallback.response_body),
  )

  effective_ssh_allow_cidrs = length(var.ssh_allow_cidrs) == 0 ? ["${local.detected_ip}/32"] : var.ssh_allow_cidrs

  # First existing key in this priority order. Override with var.ssh_private_key_path.
  ssh_key_candidates = [
    pathexpand("~/.ssh/id_rsa"),
  ]
  detected_ssh_private_key_path = try(
    [for p in local.ssh_key_candidates : p if fileexists("${p}.pub")][0],
    null,
  )

  effective_ssh_private_key_path = coalesce(var.ssh_private_key_path, local.detected_ssh_private_key_path)

  # A conditional, not coalesce: coalesce evaluates file() eagerly, and a CI runner
  # that sets TF_VAR_ssh_public_key has no ~/.ssh to read.
  effective_ssh_public_key = var.ssh_public_key != null ? var.ssh_public_key : file("${local.effective_ssh_private_key_path}.pub")
}
