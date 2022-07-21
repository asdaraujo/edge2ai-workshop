resource "azurerm_network_security_group" "workshop_cluster_sg" {
  name                = "${var.owner}-${var.name_prefix}-cluster-sg"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "egress"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "azurerm_network_security_group" "workshop_web_sg" {
  name                = "${var.owner}-${var.name_prefix}-web-sg"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "egress"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ingress"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = distinct(concat(["${var.my_public_ip}/32"], var.extra_cidr_blocks))
    destination_address_prefix = "*"
  }

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "azurerm_network_security_rule" "workshop_cluster_extra_sg_rule" {
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.workshop_cluster_sg.name
  name                        = "workshop_cluster_extra_sg_rule"
  priority                    = 101
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefixes     = distinct(concat(["${var.my_public_ip}/32"], var.extra_cidr_blocks))
  destination_address_prefix  = "*"
}

resource "azurerm_network_security_rule" "workshop_public_ips_sg_rule" {
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.workshop_cluster_sg.name
  name                        = "workshop_public_ips_sg_rule"
  priority                    = 102
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefixes     = [ for ip in azurerm_public_ip.ip_cluster.*.ip_address: "${ip}/32" ]
  destination_address_prefix  = "*"
}

#resource "aws_security_group_rule" "workshop_self_sg_rule" {
#  type              = "ingress"
#  from_port         = 0
#  to_port           = 65535
#  protocol          = "tcp"
#  self              = true
#  security_group_id = aws_security_group.workshop_cluster_sg.id
#}

