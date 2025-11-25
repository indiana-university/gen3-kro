output "role_assignment_id" {
  description = "ID of the role assignment"
  value       = var.override_id != null ? var.override_id : (var.create ? azurerm_role_assignment.this[0].id : null)
}
