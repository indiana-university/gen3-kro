output "resource_group_name" {
  description = "Name of the created resource group"
  value       = var.create ? azurerm_resource_group.this[0].name : null
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = var.create ? azurerm_resource_group.this[0].id : null
}

output "location" {
  description = "Location of the resource group"
  value       = var.create ? azurerm_resource_group.this[0].location : null
}
