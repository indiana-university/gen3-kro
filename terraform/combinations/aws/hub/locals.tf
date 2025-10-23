locals {
  # Common resource naming prefix
  name_prefix = var.cluster_name

  # VPC configuration
  vpc_id     = var.enable_vpc ? module.vpc.vpc_id : var.existing_vpc_id
  subnet_ids = var.enable_vpc ? module.vpc.private_subnets : var.existing_subnet_ids

  # EKS cluster information
  cluster_name              = var.cluster_name
  cluster_oidc_provider_arn = var.enable_eks_cluster ? module.eks_cluster.oidc_provider_arn : ""
  cluster_oidc_provider     = var.enable_eks_cluster ? module.eks_cluster.oidc_provider : ""

  # Addon services configuration from addon_configs
  addon_services_list = keys(var.addon_configs)
  addon_services_enabled = {
    for k, v in var.addon_configs : k => lookup(v, "enable_pod_identity", true)
  }

  # Common tags
  common_tags = merge(
    var.tags,
    {
      Terraform   = "true"
      ClusterName = var.cluster_name
    }
  )
}
