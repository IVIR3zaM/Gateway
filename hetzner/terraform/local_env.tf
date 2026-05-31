# Operator auto-detection. Every `terraform plan` re-fetches the public IP and
# re-reads the local SSH key, so a roaming laptop doesn't need to keep editing
# tfvars. All three are overridable via the matching variables.

data "http" "my_ip_primary" {
  url = "https://api.ipify.org"
  retry {
    attempts = 2
  }
}

# Fallback service in case ipify is down — plan would otherwise hard-fail.
data "http" "my_ip_fallback" {
  url = "https://ifconfig.me/ip"
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

  effective_ssh_public_key = coalesce(var.ssh_public_key, file("${local.effective_ssh_private_key_path}.pub"))
}
