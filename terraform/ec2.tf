# AL2023 latest x86_64 — published as a public SSM parameter, so we don't
# need ec2:DescribeImages (which the deploying IAM user may not have).
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "random_uuid" "vmess_id" {}

locals {
  v2ray_server_config = templatefile("${path.module}/templates/v2ray-server.json.tftpl", {
    uuid    = random_uuid.vmess_id.result
    ws_path = var.ws_path
  })

  nginx_config = templatefile("${path.module}/templates/nginx.conf.tftpl", {
    ws_path = var.ws_path
  })

  # Approximate sustained network baseline per instance type, in Mbps.
  # AWS publishes "up to N Gbps" with a lower sustained baseline; these are
  # rough public figures for the "always available" share. Used only as a
  # reference line in the stats panel — not a hard quota.
  instance_baseline_mbps = {
    "t3.nano"    = 32
    "t3.micro"   = 64
    "t3.small"   = 128
    "t3.medium"  = 256
    "t3.large"   = 512
    "t3.xlarge"  = 1024
    "t3.2xlarge" = 2048
    "t3a.nano"   = 32
    "t3a.micro"  = 64
    "t3a.small"  = 128
    "t3a.medium" = 256
  }
  baseline_mbps = lookup(local.instance_baseline_mbps, var.instance_type, 1000)

  stats_script = templatefile("${path.module}/templates/stats.sh.tftpl", {
    baseline_mbps = local.baseline_mbps
  })

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    v2ray_config = local.v2ray_server_config
    nginx_config = local.nginx_config
    speedtest_mb = var.speedtest_mb
    stats_script = local.stats_script
  })
}

resource "aws_security_group" "v2ray" {
  name        = "${var.name}-v2ray"
  description = "Allow HTTP from CloudFront; outbound any."
  vpc_id      = data.aws_vpc.default.id

  # CloudFront-only ingress would need the AWS-managed prefix list.
  # For a minimal first pass, allow public 80 — the only thing on :80 is nginx,
  # and v2ray itself binds to 127.0.0.1. Tighten with a prefix-list rule later.
  ingress {
    description = "HTTP (nginx fronting v2ray WS + speedtest)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "v2ray" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.v2ray.id]
  associate_public_ip_address = true
  user_data                   = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.name}-v2ray"
  }
}
