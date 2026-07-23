################################################################################
# External Secrets EKS Access
################################################################################
module "external_secrets_pod_identity" {
  count   = local.enable_external_secrets ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.8.1"

  name = "${local.name}-external-secrets-role"

  attach_external_secrets_policy = true
  external_secrets_kms_key_arns  = ["arn:aws:kms:${local.region}:*:key/${var.cluster_name}/*"]
  external_secrets_secrets_manager_arns = [
    "arn:aws:secretsmanager:${local.region}:*:secret:${var.cluster_name}/*",
    "arn:aws:secretsmanager:${local.region}:*:secret:spoke*",
    "arn:aws:secretsmanager:${local.region}:*:secret:gen3-*",
  ]
  external_secrets_ssm_parameter_arns = ["arn:aws:ssm:${local.region}:*:parameter/${var.cluster_name}/*"]
  external_secrets_create_permission  = false
  attach_custom_policy                = true
  policy_statements = [
    {
      sid       = "ecr"
      actions   = ["ecr:*"]
      resources = ["*"]
    }
  ]
  # Pod Identity Associations
  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = local.external_secrets.namespace
      service_account = local.external_secrets.service_account
    }
  }

  tags = local.tags
}
