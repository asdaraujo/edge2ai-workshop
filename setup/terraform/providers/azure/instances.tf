resource "azurerm_virtual_machine" "cluster" {
  count                            = var.cluster_count
  name                             = "${var.owner}-${var.name_prefix}-cluster-${count.index}"
  location                         = var.azure_region
  resource_group_name              = azurerm_resource_group.rg.name
  network_interface_ids            = [azurerm_network_interface.nic_cluster[count.index].id]
  vm_size                          = var.cluster_instance_type
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  depends_on = [
    azurerm_network_interface_security_group_association.cluster_nic_sg_assoc
  ]

  storage_image_reference {
    publisher = var.base_image_publisher
    offer     = var.base_image_offer
    sku       = var.base_image_sku
    version   = var.base_image_version
  }

  plan {
    publisher = var.base_image_publisher
    product   = var.base_image_offer
    name      = var.base_image_sku
  }

  storage_os_disk {
    name              = "${var.owner}-${var.name_prefix}-cluster-${count.index}-osdisk"
    managed_disk_type = "Standard_LRS"
    disk_size_gb      = 200
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    custom_data    = "#cloud-config\nbootcmd:\n  - echo \"export CLUSTER_ID=${count.index}\" >> /etc/workshop.conf"
    computer_name  = "cdp"
    admin_username = var.ssh_username
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/${var.ssh_username}/.ssh/authorized_keys"
      key_data = file(var.ssh_public_key)
    }
  }

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "azurerm_managed_disk" "cluster_disk" {
  count                = var.cluster_count
  name                 = "${var.owner}-${var.name_prefix}-cluster-${count.index}-extradisk"
  location             = var.azure_region
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 200
}

resource "azurerm_virtual_machine_data_disk_attachment" "cluster_disk_attachment" {
  count              = var.cluster_count
  managed_disk_id    = azurerm_managed_disk.cluster_disk[count.index].id
  virtual_machine_id = azurerm_virtual_machine.cluster[count.index].id
  lun                = "10"
  caching            = "ReadWrite"
}

resource "azurerm_network_interface" "nic_cluster" {
  count               = var.cluster_count
  name                = "${var.owner}-${var.name_prefix}-cluster-nic-${count.index}"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip_cluster[count.index].id
  }

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "azurerm_public_ip" "ip_cluster" {
  count               = var.cluster_count
  name                = "${var.owner}-${var.name_prefix}-cluster-ip-${count.index}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.azure_region
  allocation_method   = "Static"

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "azurerm_network_interface_security_group_association" "cluster_nic_sg_assoc" {
  count                     = var.cluster_count
  network_interface_id      = azurerm_network_interface.nic_cluster[count.index].id
  network_security_group_id = azurerm_network_security_group.workshop_cluster_sg.id
}

#================================================================================================================================

resource "azurerm_virtual_machine" "web" {
  count                            = (var.launch_web_server ? 1 : 0)
  name                             = "${var.owner}-${var.name_prefix}-web"
  location                         = var.azure_region
  resource_group_name              = azurerm_resource_group.rg.name
  network_interface_ids            = [azurerm_network_interface.nic_web[count.index].id]
  vm_size                          = "Standard_F2"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  depends_on = [
    azurerm_network_interface_security_group_association.web_nic_sg_assoc
  ]

  storage_image_reference {
    publisher = var.base_image_publisher
    offer     = var.base_image_offer
    sku       = var.base_image_sku
    version   = var.base_image_version
  }

  plan {
    publisher = var.base_image_publisher
    product   = var.base_image_offer
    name      = var.base_image_sku
  }

  storage_os_disk {
    name              = "${var.owner}-${var.name_prefix}-web-${count.index}-osdisk"
    managed_disk_type = "Standard_LRS"
    disk_size_gb      = 40
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    computer_name  = "web"
    admin_username = var.ssh_username
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/${var.ssh_username}/.ssh/authorized_keys"
      key_data = file(var.web_ssh_public_key)
    }
  }

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "azurerm_network_interface" "nic_web" {
  count               = (var.launch_web_server ? 1 : 0)
  name                = "${var.owner}-${var.name_prefix}-web-nic-${count.index}"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip_web[count.index].id
  }

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "azurerm_public_ip" "ip_web" {
  count               = (var.launch_web_server ? 1 : 0)
  name                = "${var.owner}-${var.name_prefix}-web-ip-${count.index}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.azure_region
  allocation_method   = "Static"

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "azurerm_network_interface_security_group_association" "web_nic_sg_assoc" {
  count                     = (var.launch_web_server ? 1 : 0)
  network_interface_id      = azurerm_network_interface.nic_web[count.index].id
  network_security_group_id = azurerm_network_security_group.workshop_web_sg.id
}

#================================================================================================================================

resource "azurerm_virtual_machine" "ipa" {
  count                            = (var.use_ipa ? 1 : 0)
  name                             = "${var.owner}-${var.name_prefix}-ipa"
  location                         = var.azure_region
  resource_group_name              = azurerm_resource_group.rg.name
  network_interface_ids            = [azurerm_network_interface.nic_ipa[count.index].id]
  vm_size                          = "Standard_F2"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  depends_on = [
    azurerm_network_interface_security_group_association.ipa_nic_sg_assoc
  ]

  storage_image_reference {
    publisher = var.base_image_publisher
    offer     = var.base_image_offer
    sku       = var.base_image_sku
    version   = var.base_image_version
  }

  plan {
    publisher = var.base_image_publisher
    product   = var.base_image_offer
    name      = var.base_image_sku
  }

  storage_os_disk {
    name              = "${var.owner}-${var.name_prefix}-ipa-${count.index}-osdisk"
    managed_disk_type = "Standard_LRS"
    disk_size_gb      = 40
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    computer_name  = "ipa"
    admin_username = var.ssh_username
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/${var.ssh_username}/.ssh/authorized_keys"
      key_data = file(var.ssh_public_key)
    }
  }

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "azurerm_network_interface" "nic_ipa" {
  count               = (var.use_ipa ? 1 : 0)
  name                = "${var.owner}-${var.name_prefix}-ipa-nic-${count.index}"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip_ipa[count.index].id
  }

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "azurerm_public_ip" "ip_ipa" {
  count               = (var.use_ipa ? 1 : 0)
  name                = "${var.owner}-${var.name_prefix}-ipa-ip-${count.index}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.azure_region
  allocation_method   = "Static"

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "azurerm_network_interface_security_group_association" "ipa_nic_sg_assoc" {
  count                     = (var.use_ipa ? 1 : 0)
  network_interface_id      = azurerm_network_interface.nic_ipa[count.index].id
  network_security_group_id = azurerm_network_security_group.workshop_cluster_sg.id
}
