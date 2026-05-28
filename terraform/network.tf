# The account's default VPC already has an IGW + 0.0.0.0/0 route on the main
# route table, but no subnets. We add one public subnet in eu-central-1a so
# the EC2 instance has somewhere to land. Anything launched here picks up the
# main route table by default, so we get internet access for free.

data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  vpc_id                  = data.aws_vpc.default.id
  availability_zone       = data.aws_availability_zones.available.names[0]
  cidr_block              = "172.31.0.0/20"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public"
  }
}
