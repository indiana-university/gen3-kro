resource "azurerm_user_assigned_identity" "this" {
  count = var.create ? 1 : 0

  name                = var.identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "this" {
  count = var.create ? 1 : 0

  name                = "${var.identity_name}-federated"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.this[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.cluster_oidc_issuer_url
  subject             = "system:serviceaccount:${var.namespace}:${var.service_account}"
}

resource "azurerm_role_assignment" "this" {
  count = var.create && var.role_definition_id != null && var.scope != "" ? 1 : 0

  scope              = var.scope
  role_definition_id = var.role_definition_id
  principal_id       = azurerm_user_assigned_identity.this[0].principal_id
}
