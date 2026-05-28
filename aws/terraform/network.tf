# Most AWS regions have default-VPC subnets out of the box. A few (notably the
# one Frankfurt default VPC we hit) don't — so we look first and create one
# only when none exists. The created subnet uses the first /20 slot after the
# usual default ranges to avoid CIDR conflicts in regions that *do* have them.

data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  # Only count AWS-provisioned default subnets. Without this filter the
  # data source also returns the subnet *we* create below — flipping
  # has_existing_subnet to true on the next apply and triggering a destroy
  # of the resource it just created.
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  has_existing_subnet = length(data.aws_subnets.default.ids) > 0
  subnet_id           = local.has_existing_subnet ? data.aws_subnets.default.ids[0] : aws_subnet.public[0].id
}

resource "aws_subnet" "public" {
  count                   = local.has_existing_subnet ? 0 : 1
  vpc_id                  = data.aws_vpc.default.id
  availability_zone       = data.aws_availability_zones.available.names[0]
  cidr_block              = "172.31.240.0/20"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public"
  }
}
