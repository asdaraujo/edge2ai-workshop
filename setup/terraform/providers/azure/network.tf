resource "azurerm_virtual_network" "vnet" {
  name                = "${var.owner}-${var.name_prefix}-vnet"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.owner}-${var.name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.cidr_block_1]
}

#resource "aws_internet_gateway" "igw" {
#  count  = (var.vpc_id != "" ? 0 : 1)
#  vpc_id = (var.vpc_id != "" ? var.vpc_id : aws_vpc.vpc[0].id)
#
#  tags = {
#    Name    = "${var.owner}-${var.name_prefix}-igw"
#    owner   = var.owner
#    project = var.project
#    enddate = var.enddate
#  }
#}
#
#data "aws_internet_gateway" "existing_igw" {
#  count  = (var.vpc_id != "" ? 1 : 0)
#  filter {
#    name   = "attachment.vpc-id"
#    values = [var.vpc_id]
#  }
#}
#
#resource "aws_route_table_association" "rtb_assoc" {
#  count          = (var.vpc_id != "" ? 1 : 0)
#  subnet_id      = aws_subnet.subnet1.id
#  route_table_id = aws_route_table.rtb.id
#}
#
#resource "aws_main_route_table_association" "main_rtb_assoc" {
#  count          = (var.vpc_id != "" ? 0 : 1)
#  vpc_id         = (var.vpc_id != "" ? var.vpc_id : aws_vpc.vpc[0].id)
#  route_table_id = aws_route_table.rtb.id
#}
#
#resource "aws_route_table" "rtb" {
#  vpc_id = (var.vpc_id != "" ? var.vpc_id : aws_vpc.vpc[0].id)
#
#  route {
#    cidr_block = "0.0.0.0/0"
#    gateway_id = (var.vpc_id == "" ? aws_internet_gateway.igw[0].id : data.aws_internet_gateway.existing_igw[0].internet_gateway_id)
#  }
#
#  tags = {
#    Name    = "${var.owner}-${var.name_prefix}-rtb"
#    owner   = var.owner
#    project = var.project
#    enddate = var.enddate
#  }
#}
