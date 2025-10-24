resource "azurerm_role_assignment" "this" {
  count = var.create ? 1 : 0

  scope                = var.scope
  role_definition_name = var.role_definition_name != "" ? var.role_definition_name : null
  role_definition_id   = var.custom_role_definition_id != "" ? var.custom_role_definition_id : null
  principal_id         = var.hub_managed_identity_principal_id
}
