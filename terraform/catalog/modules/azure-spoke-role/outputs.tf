output "role_assignment_id" {
  description = "ID of the role assignment"
  value       = var.create ? azurerm_role_assignment.this[0].id : null
}
