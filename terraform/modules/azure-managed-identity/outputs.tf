output "identity_id" {
  description = "ID of the managed identity"
  value       = var.create ? azurerm_user_assigned_identity.this[0].id : null
}

output "client_id" {
  description = "Client ID of the managed identity"
  value       = var.create ? azurerm_user_assigned_identity.this[0].client_id : null
}

output "principal_id" {
  description = "Principal ID of the managed identity"
  value       = var.create ? azurerm_user_assigned_identity.this[0].principal_id : null
}

output "identity_name" {
  description = "Name of the managed identity"
  value       = var.create ? azurerm_user_assigned_identity.this[0].name : null
}
