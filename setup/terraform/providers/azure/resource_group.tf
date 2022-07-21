resource "azurerm_resource_group" "rg" {
  name     = "${var.owner}-${var.name_prefix}-rg"
  location = var.azure_region

  tags = {
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}
