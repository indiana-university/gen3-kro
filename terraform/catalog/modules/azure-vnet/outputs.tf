output "vnet_id" {
  description = "ID of the VNet"
  value       = var.create ? azurerm_virtual_network.this[0].id : null
}

output "vnet_name" {
  description = "Name of the VNet"
  value       = var.create ? azurerm_virtual_network.this[0].name : null
}

output "subnet_ids" {
  description = "IDs of created subnets"
  value       = var.create ? azurerm_subnet.this[*].id : []
}
