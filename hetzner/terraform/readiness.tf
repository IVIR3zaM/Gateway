# Blue/green readiness gate. SSHes into the freshly-booted VM and waits until
# nginx + v2ray are serving on :443 before Terraform is allowed to flip the
# Cloudflare A record (see cloudflare_record.gw depends_on).
resource "null_resource" "wait_for_origin" {
  triggers = {
    server_id = hcloud_server.v2ray.id
  }

  connection {
    type        = "ssh"
    host        = hcloud_server.v2ray.ipv4_address
    user        = "root"
    private_key = file(local.effective_ssh_private_key_path)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "for i in $(seq 1 60); do curl -ksSf --max-time 5 https://localhost/ > /dev/null && echo origin-ready && exit 0; echo waiting $i/60; sleep 5; done; echo origin-never-ready >&2; exit 1",
    ]
  }
}
