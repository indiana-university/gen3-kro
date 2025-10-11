locals {
  cluster_info              = try(module.eks-hub.cluster_info, null)
  vpc_id                    = try(module.eks-hub.vpc_id, null)
  vpc_cidr                  = "10.0.0.0/16"
  use_ack                   = var.use_ack
  cluster_name              = var.cluster_name
  vpc_name                  = "${var.vpc_name}-vpc"
  environment               = var.environment
  argocd_namespace          = "argocd"
  ack_namespace             = "ack-system"
  fleet_member              = "control-plane"
  argocd_chart_version      = var.argocd_chart_version
  cluster_version           = var.kubernetes_version
  hub_profile               = var.hub_aws_profile
  hub_region                = var.hub_aws_region
      # automode/aws_load_balancer_controller will activate aws_lb_controller_pod_identity



  #compute
  azs                       = try(slice(module.eks-hub.azs, 0, 2), [])
  hub_account_id            = try(module.eks-hub.account_id, null)
  argocd_hub_pod_identity_iam_role_arn = try(module.eks-hub.argocd_hub_pod_identity_iam_role_arn, null)
  ack_hub_roles             = try(module.eks-hub.ack_hub_roles, {})

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

  gitops_addons_base_path   = length(trimspace(var.gitops_addons_repo_base_path))   > 0 ? "${trimspace(var.gitops_addons_repo_base_path)}/"   : "argocd/addons/"
  gitops_addons_path        = length(trimspace(var.gitops_addons_repo_path))        > 0 ?              trimspace(var.gitops_addons_repo_path)                     : ""
  gitops_fleet_base_path    = length(trimspace(var.gitops_fleet_repo_base_path))    > 0 ? "${trimspace(var.gitops_fleet_repo_base_path)}/"    : "argocd/fleet/"
  gitops_fleet_path         = length(trimspace(var.gitops_fleet_repo_path))         > 0 ?              trimspace(var.gitops_fleet_repo_path)                      : "kro-hub"
  gitops_platform_base_path = length(trimspace(var.gitops_platform_repo_base_path)) > 0 ? "${trimspace(var.gitops_platform_repo_base_path)}/" : "argocd/platform/"
  gitops_platform_path      = length(trimspace(var.gitops_platform_repo_path))      > 0 ?              trimspace(var.gitops_platform_repo_path)                   : ""
  gitops_workload_base_path = length(trimspace(var.gitops_workload_repo_base_path)) > 0 ? "${trimspace(var.gitops_workload_repo_base_path)}/" : "argocd/apps/"
  gitops_workload_path      = length(trimspace(var.gitops_workload_repo_path))      > 0 ?              trimspace(var.gitops_workload_repo_path)                   : "sample-web"

  gitops_repos = {
    addons = {
      url                  = "https://${var.gitops_addons_github_url}/${var.gitops_addons_org_name}/${var.gitops_addons_repo_name}.git"
      enterprise_base_url  = "https://${var.gitops_addons_github_url}/api/v3"
      path                 = local.gitops_addons_path
      base_path            = local.gitops_addons_base_path
      revision             = var.gitops_addons_repo_revision
      app_id               = var.gitops_addons_app_id
      installation_id      = var.gitops_addons_app_installation_id
      ssm_path             = var.gitops_addons_app_private_key_ssm_path
    }
    fleet = {
      url                  = "https://${var.gitops_fleet_github_url}/${var.gitops_fleet_org_name}/${var.gitops_fleet_repo_name}.git"
      enterprise_base_url  = "https://${var.gitops_fleet_github_url}/api/v3"
      path                 = local.gitops_fleet_path
      base_path            = local.gitops_fleet_base_path
      revision             = var.gitops_fleet_repo_revision
      app_id               = var.gitops_fleet_app_id
      installation_id      = var.gitops_fleet_app_installation_id
      ssm_path             = var.gitops_fleet_app_private_key_ssm_path
    }
    platform = {
      url                  = "https://${var.gitops_platform_github_url}/${var.gitops_platform_org_name}/${var.gitops_platform_repo_name}.git"
      enterprise_base_url  = "https://${var.gitops_platform_github_url}/api/v3"
      path                 = local.gitops_platform_path
      base_path            = local.gitops_platform_base_path
      revision             = var.gitops_platform_repo_revision
      app_id               = var.gitops_platform_app_id
      installation_id      = var.gitops_platform_app_installation_id
      ssm_path             = var.gitops_platform_app_private_key_ssm_path
    }
    workload = {
      url                  = "https://${var.gitops_workload_github_url}/${var.gitops_workload_org_name}/${var.gitops_workload_repo_name}.git"
      enterprise_base_url  = "https://${var.gitops_workload_github_url}/api/v3"
      path                 = local.gitops_workload_path
      base_path            = local.gitops_workload_base_path
      revision             = var.gitops_workload_repo_revision
      app_id               = var.gitops_workload_app_id
      installation_id      = var.gitops_workload_app_installation_id
      ssm_path             = var.gitops_workload_app_private_key_ssm_path
    }
  }



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
    enable_argocd                          = try(var.addons.enable_argocd, false)
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
      hub_account_id                  = module.eks-hub.account_id
      hub_cluster_name                = local.cluster_info.cluster_name
      hub_aws_region                  = local.hub_region
      environment                     = local.environment
      aws_vpc_id                      = local.vpc_id
      use_ack                         = local.use_ack
      # Add tenants annotation with list of spoke aliases
      tenants                         = jsonencode([for spoke in var.spokes : spoke.alias])
    },
    {
      argocd_namespace        = local.argocd_namespace,
      create_argocd_namespace = false,
      argocd_controller_role_arn = local.argocd_hub_pod_identity_iam_role_arn
    },
    {
      addons_repo_url      = local.gitops_repos["addons"].url
      addons_repo_path     = local.gitops_repos["addons"].path
      addons_repo_basepath = local.gitops_repos["addons"].base_path
      addons_repo_revision = local.gitops_repos["addons"].revision
    },
    {
      workload_repo_url      = local.gitops_repos["workload"].url
      workload_repo_path     = local.gitops_repos["workload"].path
      workload_repo_basepath = local.gitops_repos["workload"].base_path
      workload_repo_revision = local.gitops_repos["workload"].revision
    },
    {
      fleet_repo_url      = local.gitops_repos["fleet"].url
      fleet_repo_path     = local.gitops_repos["fleet"].path
      fleet_repo_basepath = local.gitops_repos["fleet"].base_path
      fleet_repo_revision = local.gitops_repos["fleet"].revision
    },
    {
      platform_repo_url      = local.gitops_repos["platform"].url
      platform_repo_path     = local.gitops_repos["platform"].path
      platform_repo_basepath = local.gitops_repos["platform"].base_path
      platform_repo_revision = local.gitops_repos["platform"].revision
    },
    {
      external_secrets_namespace       = local.external_secrets.namespace
      external_secrets_service_account = local.external_secrets.service_account
    },
    {
      for service, cfg in local.ack_services_config :
      "ack_${service}_service_account" => cfg.service_account
    },
    {
      for service, cfg in local.ack_services_config :
      "ack_${service}_namespace" => cfg.namespace
    },
    #---------------------------------------------------------------------------------------#
    # ACK Hub Role ARNs from eks-hub module - keyed by "<service>-ack-controller"
    #---------------------------------------------------------------------------------------#
    {
      # ACK Hub Role ARNs from eks-hub module - keyed by "<hub-alias>-<service>-ack-arn"
      for service, role in local.ack_hub_roles :
      "${var.hub_alias}-${service}-ack-arn" => role.arn
    },
    #---------------------------------------------------------------------------------------#
    # Role ARNs from IAM access modules (generated by Terragrunt per spoke)
    # The ack_spoke_role_arns_by_spoke local is defined in iam-access-modules.tf
    # generated by Terragrunt generate block
    #---------------------------------------------------------------------------------------#
    # Flatten spoke role ARNs keyed by "<spoke>-<ack>-ack-controller"
    merge([
      for spoke_alias, arn_maps in try(local.ack_spoke_role_arns_by_spoke, {}) : {
        for service, arn in arn_maps :
          "${spoke_alias}-${service}-ack-arn" => arn
      }
    ]...),
    #---------------------------------------------------------------------------------------#
    # Spoke Account IDs from IAM access modules
    # The iam_access_modules_data local is defined in iam-access-modules.tf
    # generated by Terragrunt generate block
    # Exposes spoke account IDs as annotations: spoke_<alias>_account_id
    #---------------------------------------------------------------------------------------#
    {
      for spoke_alias, spoke_data in try(local.iam_access_modules_data, {}) :
      "${spoke_alias}_account_id" => try(spoke_data.account_id, null)
    },
    {
      aws_load_balancer_controller_namespace       = local.aws_load_balancer_controller.namespace
      aws_load_balancer_controller_service_account = local.aws_load_balancer_controller.service_account
    },
  )

  argocd_apps = {
    applicationsets = file("${path.module}/applicationsets.yaml")
  }
  argocd_cluster_data = {
    cluster_name = try(local.cluster_info.cluster_name, null)
    environment  = local.environment
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
  # Filter repos that have non-empty ssm_path → private repos
  # These will use the ESO to fetch the private key from SSM using the ssm_path provided
  gitops_private_repos = {
    for k, v in local.gitops_repos :
    k => v     if
      (
        try(v.url, "")               != "" &&
        try(v.ssm_path, "")          != "" &&
        try(v.app_id, null)          != null &&
        try(v.installation_id, null) != null
      )
  }

  tags = merge(
    var.tags,
    {
      Blueprint  = local.cluster_name
      Environment = local.environment
      ManagedBy  = "Terraform-AgroCD"
    }
  )
}
