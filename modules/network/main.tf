# ---------------------------------------------------------------
# VPC
# ---------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# ---------------------------------------------------------------
# Subnets: 3 tiers x 2 AZs
# ---------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # name = { tier, AZ index (0 = a, 1 = b), netnum for cidrsubnet(/16 + 8 = /24) }
  subnets = {
    "public-a"       = { tier = "public", az = 0, netnum = 0 }
    "public-b"       = { tier = "public", az = 1, netnum = 1 }
    "private-app-a"  = { tier = "private-app", az = 0, netnum = 10 }
    "private-app-b"  = { tier = "private-app", az = 1, netnum = 11 }
    "private-data-a" = { tier = "private-data", az = 0, netnum = 20 }
    "private-data-b" = { tier = "private-data", az = 1, netnum = 21 }
  }

  # { "public" = ["public-a", "public-b"], "private-app" = [...], "private-data" = [...] }
  subnet_keys_by_tier = {
    for tier in ["public", "private-app", "private-data"] :
    tier => [for key, s in local.subnets : key if s.tier == tier]
  }
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value.netnum)
  availability_zone       = local.azs[each.value.az]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-${each.key}"
    Tier = each.value.tier
  }
}

# ---------------------------------------------------------------
# Internet gateway + public routing
# ---------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# ---------------------------------------------------------------
# NAT gateways (0 in dev, 1 in preprod, 2 in prod)
# ---------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = var.nat_gateway_count
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip-${count.index}"
  }
}

resource "aws_nat_gateway" "this" {
  count = var.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.this[local.subnet_keys_by_tier["public"][count.index]].id

  tags = {
    Name = "${var.name_prefix}-nat-${count.index}"
  }

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------
# Private-app routing: one route table per AZ, default route to NAT only if NAT exists
# ---------------------------------------------------------------
resource "aws_route_table" "private_app" {
  count  = length(local.azs)
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-private-app-rt-${count.index}"
  }
}

resource "aws_route" "private_app_nat" {
  count = var.nat_gateway_count > 0 ? length(local.azs) : 0

  route_table_id         = aws_route_table.private_app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  # 2 NATs: each AZ uses its own. 1 NAT: both AZs share NAT 0.
  nat_gateway_id = aws_nat_gateway.this[min(count.index, var.nat_gateway_count - 1)].id
}

# ---------------------------------------------------------------
# Private-data routing: no internet route at all
# ---------------------------------------------------------------
resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-private-data-rt"
  }
}

# ---------------------------------------------------------------
# Route table associations
# ---------------------------------------------------------------
resource "aws_route_table_association" "this" {
  for_each = local.subnets

  subnet_id = aws_subnet.this[each.key].id
  route_table_id = (
    each.value.tier == "public" ? aws_route_table.public.id :
    each.value.tier == "private-app" ? aws_route_table.private_app[each.value.az].id :
    aws_route_table.private_data.id
  )
}

# ---------------------------------------------------------------
# S3 gateway endpoint (free): S3 traffic stays inside AWS, no NAT cost
# ---------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id, aws_route_table.private_data.id],
    aws_route_table.private_app[*].id,
  )

  tags = {
    Name = "${var.name_prefix}-s3-endpoint"
  }
}