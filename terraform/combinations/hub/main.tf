###############################################################################
# VPC Module
###############################################################################
module "vpc" {
  source = "../../modules/vpc"

  create = var.enable_vpc

  vpc_name            = var.vpc_name
  vpc_cidr            = var.vpc_cidr
  cluster_name        = var.cluster_name
  enable_nat_gateway  = var.enable_nat_gateway
  single_nat_gateway  = var.single_nat_gateway
  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags

  tags = merge(
    var.tags,
    var.vpc_tags
  )
}

###############################################################################
# EKS Cluster Module
###############################################################################
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  create = var.enable_vpc && var.enable_eks_cluster

  cluster_name                             = var.cluster_name
  cluster_version                          = var.cluster_version
  vpc_id                                   = var.enable_vpc ? module.vpc.vpc_id : var.existing_vpc_id
  subnet_ids                               = var.enable_vpc ? module.vpc.private_subnets : var.existing_subnet_ids
  cluster_endpoint_public_access           = var.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  cluster_compute_config                   = var.cluster_compute_config

  tags = merge(
    var.tags,
    var.eks_cluster_tags
  )

  depends_on = [module.vpc]
}

###############################################################################
# ACK IAM Policy Module
###############################################################################
module "same_account" {
  source = "../../modules/ack-iam-policy"

  for_each = var.ack_services

  create = var.enable_ack_same_account && lookup(each.value, "enabled", true)

  service_name           = each.key
  override_policy_path   = lookup(each.value, "override_policy_path", "")
  override_policy_url    = lookup(each.value, "override_policy_url", "")
  additional_policy_arns = lookup(each.value, "additional_policy_arns", {})
}

###############################################################################
# ACK Enhanced Pod Identity Module
###############################################################################
module "ack" {
  source = "../../modules/ack-enhanced-pod-identity"

  for_each = var.ack_services

  create = var.enable_vpc && var.enable_eks_cluster && var.enable_ack && lookup(each.value, "enabled", true)

  cluster_name              = var.cluster_name
  service_name              = each.key
  cross_account_policy_json = null
  override_policy_documents = []
  additional_policy_arns    = {}
  trust_policy_conditions   = lookup(each.value, "trust_policy_conditions", [])
  association_defaults      = lookup(each.value, "association_defaults", {})
  associations              = lookup(each.value, "associations", {})

  tags = merge(
    var.tags,
    var.ack_tags,
    lookup(each.value, "tags", {})
  )

  depends_on = [module.eks_cluster, module.same_account]
}

###############################################################################
# Cross Account Policy Module
###############################################################################
module "cross_account_policy" {
  source = "../../modules/cross-account-policy"

  for_each = var.ack_cross_account_policies

  create = lookup(each.value, "enabled", true)

  service_name              = each.key
  hub_pod_identity_role_arn = try(module.ack[each.key].role_arn, "")
  spoke_role_arns           = lookup(each.value, "spoke_role_arns", [])

  tags = merge(
    var.tags,
    var.cross_account_policy_tags,
    lookup(each.value, "tags", {})
  )

}
###############################################################################
# ArgoCD Pod Identity Module
###############################################################################
module "argocd_pod_identity" {
  source = "../../modules/argocd-pod-identity"

  create = var.enable_vpc && var.enable_eks_cluster && var.enable_argocd

  cluster_name         = var.cluster_name
  has_inline_policy    = true
  source_policy_documents = [
    file("${path.root}/../../iam/ack-permissions/argocd/recommended-inline-policy")
  ]

  association_defaults = {
    namespace = var.argocd_namespace
  }

  associations = {
    controller = {
      cluster_name    = var.cluster_name
      service_account = "argocd-application-controller"
    }
    server = {
      cluster_name    = var.cluster_name
      service_account = "argocd-server"
    }
    repo-server = {
      cluster_name    = var.cluster_name
      service_account = "argocd-repo-server"
    }
  }

  tags = merge(
    var.tags,
    var.addons_pod_identities_tags
  )

  depends_on = [module.eks_cluster]
}
###############################################################################
# Addons Pod Identities Module
###############################################################################
module "addons" {
  source = "../../modules/addons-pod-identities"

  create = var.enable_vpc && var.enable_eks_cluster

  cluster_name = var.cluster_name

  # EBS CSI Driver
  enable_aws_ebs_csi      = var.enable_aws_ebs_csi
  ebs_csi_kms_arns        = var.ebs_csi_kms_arns
  ebs_csi_namespace       = var.ebs_csi_namespace
  ebs_csi_service_account = var.ebs_csi_service_account

  # External Secrets
  enable_external_secrets               = var.enable_external_secrets
  external_secrets_kms_key_arns         = var.external_secrets_kms_key_arns
  external_secrets_secrets_manager_arns = var.external_secrets_secrets_manager_arns
  external_secrets_ssm_parameter_arns   = var.external_secrets_ssm_parameter_arns
  external_secrets_create_permission    = var.external_secrets_create_permission
  external_secrets_attach_custom_policy = var.external_secrets_attach_custom_policy
  external_secrets_policy_statements    = var.external_secrets_policy_statements
  external_secrets_namespace            = var.external_secrets_namespace
  external_secrets_service_account      = var.external_secrets_service_account

  # AWS Load Balancer Controller
  enable_aws_load_balancer_controller          = var.enable_aws_load_balancer_controller
  aws_load_balancer_controller_namespace       = var.aws_load_balancer_controller_namespace
  aws_load_balancer_controller_service_account = var.aws_load_balancer_controller_service_account

  # ArgoCD Pod Identity (disabled - using separate module)
  enable_argocd    = false
  argocd_namespace = var.argocd_namespace

  # Amazon Managed Service for Prometheus
  enable_amazon_managed_service_prometheus          = var.enable_amazon_managed_service_prometheus
  amazon_managed_service_prometheus_workspace_arns  = var.amazon_managed_service_prometheus_workspace_arns
  amazon_managed_service_prometheus_namespace       = var.amazon_managed_service_prometheus_namespace
  amazon_managed_service_prometheus_service_account = var.amazon_managed_service_prometheus_service_account

  # AWS AppMesh Controller
  enable_aws_appmesh_controller          = var.enable_aws_appmesh_controller
  aws_appmesh_controller_namespace       = var.aws_appmesh_controller_namespace
  aws_appmesh_controller_service_account = var.aws_appmesh_controller_service_account

  # AWS AppMesh Envoy Proxy
  enable_aws_appmesh_envoy_proxy          = var.enable_aws_appmesh_envoy_proxy
  aws_appmesh_envoy_proxy_namespace       = var.aws_appmesh_envoy_proxy_namespace
  aws_appmesh_envoy_proxy_service_account = var.aws_appmesh_envoy_proxy_service_account

  # AWS CloudWatch Observability
  enable_aws_cloudwatch_observability          = var.enable_aws_cloudwatch_observability
  aws_cloudwatch_observability_namespace       = var.aws_cloudwatch_observability_namespace
  aws_cloudwatch_observability_service_account = var.aws_cloudwatch_observability_service_account

  # AWS EFS CSI
  enable_aws_efs_csi          = var.enable_aws_efs_csi
  aws_efs_csi_namespace       = var.aws_efs_csi_namespace
  aws_efs_csi_service_account = var.aws_efs_csi_service_account

  # AWS FSx for Lustre CSI
  enable_aws_fsx_lustre_csi            = var.enable_aws_fsx_lustre_csi
  aws_fsx_lustre_csi_service_role_arns = var.aws_fsx_lustre_csi_service_role_arns
  aws_fsx_lustre_csi_namespace         = var.aws_fsx_lustre_csi_namespace
  aws_fsx_lustre_csi_service_account   = var.aws_fsx_lustre_csi_service_account

  # AWS Gateway Controller
  enable_aws_gateway_controller          = var.enable_aws_gateway_controller
  aws_gateway_controller_namespace       = var.aws_gateway_controller_namespace
  aws_gateway_controller_service_account = var.aws_gateway_controller_service_account

  # AWS Load Balancer Controller TargetGroup Binding Only
  enable_aws_lb_controller_targetgroup_binding_only          = var.enable_aws_lb_controller_targetgroup_binding_only
  aws_lb_controller_targetgroup_arns                         = var.aws_lb_controller_targetgroup_arns
  aws_lb_controller_targetgroup_binding_only_namespace       = var.aws_lb_controller_targetgroup_binding_only_namespace
  aws_lb_controller_targetgroup_binding_only_service_account = var.aws_lb_controller_targetgroup_binding_only_service_account

  # AWS Node Termination Handler
  enable_aws_node_termination_handler          = var.enable_aws_node_termination_handler
  aws_node_termination_handler_sqs_queue_arns  = var.aws_node_termination_handler_sqs_queue_arns
  aws_node_termination_handler_namespace       = var.aws_node_termination_handler_namespace
  aws_node_termination_handler_service_account = var.aws_node_termination_handler_service_account

  # AWS Private CA Issuer
  enable_aws_privateca_issuer          = var.enable_aws_privateca_issuer
  aws_privateca_issuer_acmca_arns      = var.aws_privateca_issuer_acmca_arns
  aws_privateca_issuer_namespace       = var.aws_privateca_issuer_namespace
  aws_privateca_issuer_service_account = var.aws_privateca_issuer_service_account

  # AWS VPC CNI IPv4
  enable_aws_vpc_cni_ipv4          = var.enable_aws_vpc_cni_ipv4
  aws_vpc_cni_ipv4_namespace       = var.aws_vpc_cni_ipv4_namespace
  aws_vpc_cni_ipv4_service_account = var.aws_vpc_cni_ipv4_service_account

  # AWS VPC CNI IPv6
  enable_aws_vpc_cni_ipv6          = var.enable_aws_vpc_cni_ipv6
  aws_vpc_cni_ipv6_namespace       = var.aws_vpc_cni_ipv6_namespace
  aws_vpc_cni_ipv6_service_account = var.aws_vpc_cni_ipv6_service_account

  # Cert Manager
  enable_cert_manager           = var.enable_cert_manager
  cert_manager_hosted_zone_arns = var.cert_manager_hosted_zone_arns
  cert_manager_namespace        = var.cert_manager_namespace
  cert_manager_service_account  = var.cert_manager_service_account

  # Cluster Autoscaler
  enable_cluster_autoscaler          = var.enable_cluster_autoscaler
  cluster_autoscaler_cluster_names   = var.cluster_autoscaler_cluster_names
  cluster_autoscaler_namespace       = var.cluster_autoscaler_namespace
  cluster_autoscaler_service_account = var.cluster_autoscaler_service_account

  # External DNS
  enable_external_dns           = var.enable_external_dns
  external_dns_hosted_zone_arns = var.external_dns_hosted_zone_arns
  external_dns_namespace        = var.external_dns_namespace
  external_dns_service_account  = var.external_dns_service_account

  # Mountpoint S3 CSI
  enable_mountpoint_s3_csi           = var.enable_mountpoint_s3_csi
  mountpoint_s3_csi_bucket_arns      = var.mountpoint_s3_csi_bucket_arns
  mountpoint_s3_csi_bucket_path_arns = var.mountpoint_s3_csi_bucket_path_arns
  mountpoint_s3_csi_namespace        = var.mountpoint_s3_csi_namespace
  mountpoint_s3_csi_service_account  = var.mountpoint_s3_csi_service_account

  # Velero
  enable_velero              = var.enable_velero
  velero_s3_bucket_arns      = var.velero_s3_bucket_arns
  velero_s3_bucket_path_arns = var.velero_s3_bucket_path_arns
  velero_namespace           = var.velero_namespace
  velero_service_account     = var.velero_service_account

  tags = merge(
    var.tags,
    var.addons_pod_identities_tags
  )

  depends_on = [module.eks_cluster]
}

###############################################################################
# ArgoCD Module
###############################################################################
module "argocd" {
  source = "../../modules/argocd"

  create = var.enable_vpc && var.enable_eks_cluster && var.enable_argocd

  argocd      = var.argocd_config
  install     = var.argocd_install
  cluster     = var.argocd_cluster
  apps        = var.argocd_apps
  outputs_dir = var.argocd_outputs_dir

  depends_on = [module.eks_cluster, module.addons]
}
