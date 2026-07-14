locals {
  name             = var.csoc_alias
  region           = data.aws_region.current.region
  oidc_provider_id = replace(var.cluster_oidc_issuer_url, "https://", "")
  ack_namespace    = var.ack_namespace

  ack_aws_managed     = var.ack_management_type == "aws_managed"
  kro_aws_managed     = var.kro_management_type == "aws_managed"
  argocd_aws_managed  = var.argocd_management_type == "aws_managed"
  argocd_self_managed = var.argocd_management_type == "self_managed"

  ack_role_enabled = var.enable_ack_capability || var.enable_ack_self_managed

  external_secrets = {
    namespace       = var.external_secrets_namespace
    service_account = var.external_secrets_service_account
  }

  enable_external_secrets = try(var.addons.enable_external_secrets, false)

  tags = merge(
    {
      Blueprint   = local.name
      Environment = var.environment
    },
    var.tags
  )
}
