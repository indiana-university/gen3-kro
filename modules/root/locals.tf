locals {
  cluster_info              = try(module.eks-hub.cluster_info, null)
  cluster_exists            = try(module.eks-hub.cluster_info.cluster_name, null) != null
  vpc_id                    = try(module.eks-hub.vpc_id, null)
  vpc_cidr                  = "10.0.0.0/16"
  use_ack                   = var.use_ack
  cluster_name              = var.cluster_name
  vpc_name                  = "${var.vpc_name}-vpc"
  argocd_namespace          = "argocd"
  ack_namespace             = "ack-system"
  fleet_member              = "control-plane"
  argocd_chart_version      = var.argocd_chart_version
  cluster_version           = var.kubernetes_version
  hub_profile               = var.aws_profile
  hub_region                = var.hub_aws_region
      # automode/aws_load_balancer_controller will activate aws_lb_controller_pod_identity



  #compute
  azs                       = try(slice(module.eks-hub.azs, 0, 2), [])
  hub_account_id            = try(module.eks-hub.account_id, null)
  argocd_hub_pod_identity_iam_role_arn = try(module.eks-hub.argocd_hub_pod_identity_iam_role_arn, null)
  ack_hub_roles             = try(module.eks-hub.ack_hub_roles, {})
  ack_spoke_role_arns_by_spoke = {}  # Empty for now, populated when spokes are enabled
  iam_access_modules_data      = {}  # Empty for now, populated when cross-account IAM is enabled

  external_secrets = {
    namespace       = "external-secrets"
    service_account = "external-secrets-sa"
  }

  aws_load_balancer_controller = {
    namespace       = "kube-system"
    service_account = "aws-load-balancer-controller-sa"
  }

  ack_services_config = {
    for service in var.ack_services :
    service => {
      namespace       = local.ack_namespace
      service_account = "ack-${service}-controller"
    }
  }

  # GitOps configuration - simplified with separate repo URLs
  gitops_hub_repo_url    = var.gitops_hub_repo_url
  gitops_rgds_repo_url   = var.gitops_rgds_repo_url
  gitops_spokes_repo_url = var.gitops_spokes_repo_url
  gitops_branch          = var.gitops_branch
  gitops_bootstrap_path  = var.gitops_bootstrap_path
  gitops_rgds_path       = var.gitops_rgds_path
  gitops_spokes_path     = var.gitops_spokes_path


  tags = merge(
    var.tags,
    {
      Blueprint = local.cluster_name
      ManagedBy = "Terraform-ArgoCD"
    }
  )
}
