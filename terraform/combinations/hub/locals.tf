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

  # ACK services configuration
  ack_services_list = var.enable_ack ? keys(var.ack_services) : []
  ack_services_enabled = var.enable_ack ? {
    for k, v in var.ack_services : k => lookup(v, "enabled", true)
  } : {}

  # ACK spoke accounts configuration
  ack_spoke_accounts_list = var.enable_ack_spoke_roles ? keys(var.ack_spoke_accounts) : []
  ack_spoke_accounts_enabled = var.enable_ack_spoke_roles ? {
    for k, v in var.ack_spoke_accounts : k => lookup(v, "enabled", true)
  } : {}

  # Common tags
  common_tags = merge(
    var.tags,
    {
      Terraform   = "true"
      ClusterName = var.cluster_name
    }
  )

}
