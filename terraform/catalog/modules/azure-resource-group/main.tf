resource "azurerm_resource_group" "this" {
  count = var.create ? 1 : 0

  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}
