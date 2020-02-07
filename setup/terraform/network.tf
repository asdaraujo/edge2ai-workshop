resource "aws_vpc" "vpc" {
  count                = (var.vpc_id != "" ? 0 : 1)
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.owner}-${var.name_prefix}-vpc"
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "aws_internet_gateway" "igw" {
  count  = (var.vpc_id != "" ? 0 : 1)
  vpc_id = (var.vpc_id != "" ? var.vpc_id : aws_vpc.vpc[0].id)

  tags = {
    Name    = "${var.owner}-${var.name_prefix}-igw"
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

data "aws_internet_gateway" "existing_igw" {
  count  = (var.vpc_id != "" ? 1 : 0)
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

resource "aws_route_table_association" "rtb_assoc" {
  count          = (var.vpc_id != "" ? 1 : 0)
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.rtb.id
}

resource "aws_main_route_table_association" "main_rtb_assoc" {
  count          = (var.vpc_id != "" ? 0 : 1)
  vpc_id         = (var.vpc_id != "" ? var.vpc_id : aws_vpc.vpc[0].id)
  route_table_id = aws_route_table.rtb.id
}

resource "aws_route_table" "rtb" {
  vpc_id = (var.vpc_id != "" ? var.vpc_id : aws_vpc.vpc[0].id)

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = (var.vpc_id == "" ? aws_internet_gateway.igw[0].id : data.aws_internet_gateway.existing_igw[0].internet_gateway_id)
  }

  tags = {
    Name    = "${var.owner}-${var.name_prefix}-rtb"
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "aws_subnet" "subnet1" {
  vpc_id                  = (var.vpc_id != "" ? var.vpc_id : aws_vpc.vpc[0].id)
  cidr_block              = var.cidr_block_1
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.owner}-${var.name_prefix}-subnet1"
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}
