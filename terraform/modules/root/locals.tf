locals {
  cluster_info              = try(module.eks-hub.cluster_info, null)
  cluster_exists            = try(module.eks-hub.cluster_info.cluster_name, null) != null
  vpc_id                    = try(module.eks-hub.vpc_id, null)
  vpc_cidr                  = "10.0.0.0/16"
  use_ack                   = var.use_ack
  cluster_name              = var.cluster_name
  old_cluster_name          = var.old_cluster_name
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


  aws_addons = {
    enable_aws_ebs_csi_resources                 = try(var.addons.enable_aws_ebs_csi_resources, false)
    enable_aws_load_balancer_controller          = try(var.addons.enable_aws_load_balancer_controller, false)
    enable_external_secrets                      = try(var.addons.enable_external_secrets, false)
    enable_kro                                   = try(var.addons.enable_kro, false)
    enable_kro_eks_rgs                           = try(var.addons.enable_kro_eks_rgs, false)
    # ACK Controller enable flags for ApplicationSet selection
    enable_ack_iam                               = try(var.addons.enable_ack_iam, false)
    enable_ack_eks                               = try(var.addons.enable_ack_eks, false)
    enable_ack_ec2                               = try(var.addons.enable_ack_ec2, false)
    enable_ack_efs                               = try(var.addons.enable_ack_efs, false)
  }

  oss_addons = {
    enable_argocd = try(var.enable_argo, try(var.addons.enable_argocd, false))
  }

  addons = merge(
    local.aws_addons,
    local.oss_addons,
    { fleet_member = local.fleet_member },
    { kubernetes_version = local.cluster_version },
    { aws_cluster_name = try(local.cluster_info.cluster_name, null) },
    # Removed single tenant label - use tenants annotation (JSON array) instead for multi-tenant support
    { hub_cluster_name = try(local.cluster_info.cluster_name, local.cluster_name) }, # Hub cluster name label
  )

  # canonical keys expected by downstream templates / ApplicationSets
  addons_metadata = merge(
    {
      hub_account_id   = module.eks-hub.account_id
      hub_cluster_name = local.cluster_info.cluster_name
      hub_aws_region   = local.hub_region
      aws_vpc_id       = local.vpc_id
      use_ack          = local.use_ack
      tenants          = yamlencode([for spoke in var.spokes : spoke.alias])
    },
    {
      argocd_namespace           = local.argocd_namespace,
      create_argocd_namespace    = false,
      argocd_controller_role_arn = local.argocd_hub_pod_identity_iam_role_arn
    },
    {
      hub_repo_url     = local.gitops_hub_repo_url
      hub_repo_revision = local.gitops_branch
      hub_repo_basepath = "argocd"
      rgds_repo_url    = local.gitops_rgds_repo_url
      spokes_repo_url  = local.gitops_spokes_repo_url
      branch           = local.gitops_branch
      bootstrap_path   = local.gitops_bootstrap_path
      rgds_path        = local.gitops_rgds_path
      spokes_path      = local.gitops_spokes_path
    },
    {
      external_secrets_namespace       = local.external_secrets.namespace
      external_secrets_service_account = local.external_secrets.service_account
    },
    {
      aws_load_balancer_controller_namespace       = local.aws_load_balancer_controller.namespace
      aws_load_balancer_controller_service_account = local.aws_load_balancer_controller.service_account
    },
    # Flatten ACK controller configs into individual annotations
    # Hub role ARNs
    {
      for service, cfg in local.ack_services_config :
      "ack_${service}_hub_role_arn" => try(local.ack_hub_roles[service].arn, "")
    },
    # Namespaces
    {
      for service, cfg in local.ack_services_config :
      "ack_${service}_namespace" => cfg.namespace
    },
    # Service accounts
    {
      for service, cfg in local.ack_services_config :
      "ack_${service}_service_account" => cfg.service_account
    },
    # Spoke role ARNs - flatten completely
    merge([
      for service, cfg in local.ack_services_config : {
        for spoke_alias, arn_maps in try(local.ack_spoke_role_arns_by_spoke, {}) :
        "ack_${service}_spoke_role_arn_${spoke_alias}" => try(arn_maps[service], "")
      }
    ]...),
    {
      for spoke_alias, spoke_data in try(local.iam_access_modules_data, {}) :
      "${spoke_alias}_account_id" => try(spoke_data.account_id, null)
    },
  )

  argocd_apps = {
    applicationsets = file("${path.module}/applicationsets.yaml")
  }
  argocd_cluster_data = {
    cluster_name = try(local.cluster_info.cluster_name, null)
    metadata     = local.addons_metadata
    addons       = local.addons
  }

  argocd_settings = {
    name             = "argocd"
    namespace        = local.argocd_namespace
    chart_version    = local.argocd_chart_version
    values           = [file("${path.module}/argocd-initial-values.yaml")]
    timeout          = 600
    create_namespace = false
  }

  tags = merge(
    var.tags,
    {
      Blueprint = local.cluster_name
      ManagedBy = "Terraform-ArgoCD"
    }
  )
}
