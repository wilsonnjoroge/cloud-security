# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-VPC1"
  }
}

# ---------------------------------------------------------------------------
# Subnets -- public in AZ-a, private in AZ-b. Same VPC, so they can reach
# each other regardless of AZ; splitting AZs only affects availability, not
# reachability.
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.public_az
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet1"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.private_az
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-subnet1"
  }
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-IG1"
  }
}

# ---------------------------------------------------------------------------
# Public route table: 0.0.0.0/0 -> IGW, associated with the public subnet.
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-public-rt1"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Private route table: local traffic only (no 0.0.0.0/0 route -- there's no
# NAT Gateway). Created explicitly rather than relying on the implicit main
# route table, so it's visible and named in the console/state.
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-private-rt1"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flowlogs.arn
  iam_role_arn         = aws_iam_role.flowlogs.arn
}


resource "aws_cloudwatch_log_group" "flowlogs" {
  name              = "/aws/vpc/${var.project_name}/flowlogs"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.flowlogs.arn
}