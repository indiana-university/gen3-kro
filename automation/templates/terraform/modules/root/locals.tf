locals {
  cluster_info              = module.eks-hub.cluster_info
  vpc_id                    = module.eks-hub.vpc_id
  vpc_cidr                  = "10.0.0.0/16"
  azs                       = slice(module.eks-hub.azs, 0, 2)
  enable_automode           = var.enable_automode
  use_ack                   = var.use_ack
  enable_efs                = var.enable_efs
  name                      = var.cluster_name
  environment               = var.environment
  fleet_member              = "control-plane"
  tenant                    = var.tenant
  region                    = var.aws_region
  cluster_version           = var.kubernetes_version
  argocd_namespace          = "argocd"

  account_ids        = var.account_ids
  policy_arn_urls    = var.policy_arn_urls
  inline_policy_urls = var.inline_policy_urls
  argocd_hub_pod_identity_iam_role_arn = module.eks-hub.argocd_hub_pod_identity_iam_role_arn

  valid_policies = {
    for k, v in module.eks-hub.policy_arn : k => v.status_code == 200 ? trimspace(v.body) : null
  }

  gitops_addons_repo_url   = "https://${var.gitops_addons_github_url}/${var.gitops_addons_org_name}/${var.gitops_addons_repo_name}.git"
  gitops_fleet_repo_url    = "https://${var.gitops_fleet_github_url}/${var.gitops_fleet_org_name}/${var.gitops_fleet_repo_name}.git"
  gitops_workload_repo_url = "https://${var.gitops_workload_github_url}/${var.gitops_workload_org_name}/${var.gitops_workload_repo_name}.git"
  gitops_platform_repo_url = "https://${var.gitops_platform_github_url}/${var.gitops_platform_org_name}/${var.gitops_platform_repo_name}.git"

  gitops_app_private_key_ssm_path   = {
    addons     = var.gitops_addons_app_private_key_ssm_path
    fleet      = var.gitops_fleet_app_private_key_ssm_path
    workload   = var.gitops_workload_app_private_key_ssm_path
    platform   = var.gitops_platform_app_private_key_ssm_path
  }

  private_key_paths = distinct(values(local.gitops_app_private_key_ssm_path))

  integrations = {
    "${local.gitops_app_private_key_ssm_path.addons}" = {
      repo_url             = local.gitops_addons_repo_url
      enterprise_base_url  = "https://${var.gitops_addons_github_url}/api/v3"
      app_id               = var.gitops_addons_app_id
      installation_id      = var.gitops_addons_app_installation_id
      private_key_ssm_path = var.gitops_addons_app_private_key_ssm_path
    }
    "${local.gitops_app_private_key_ssm_path.fleet}" = {
      repo_url             = local.gitops_fleet_repo_url
      enterprise_base_url  = "https://${var.gitops_fleet_github_url}/api/v3"
      app_id               = var.gitops_fleet_app_id
      installation_id      = var.gitops_fleet_app_installation_id
      private_key_ssm_path = var.gitops_fleet_app_private_key_ssm_path
    }
    "${local.gitops_app_private_key_ssm_path.workload}" = {
      repo_url             = local.gitops_workload_repo_url
      enterprise_base_url  = "https://${var.gitops_workload_github_url}/api/v3"
      app_id               = var.gitops_workload_app_id
      installation_id      = var.gitops_workload_app_installation_id
      private_key_ssm_path = var.gitops_workload_app_private_key_ssm_path
    }
    "${local.gitops_app_private_key_ssm_path.platform}" = {
      repo_url             = local.gitops_platform_repo_url
      enterprise_base_url  = "https://${var.gitops_platform_github_url}/api/v3"
      app_id               = var.gitops_platform_app_id
      installation_id      = var.gitops_platform_app_installation_id
      private_key_ssm_path = var.gitops_platform_app_private_key_ssm_path
    }
  }

  git_secrets = {
    for path in local.private_key_paths :
    path => module.eks-hub.private_keys[path].value
  }

  external_secrets = {
    namespace       = "external-secrets"
    service_account = "external-secrets-sa"
  }
  aws_load_balancer_controller = {
    namespace       = "kube-system"
    service_account = "aws-load-balancer-controller-sa"
  }

  # karpenter = {
  #   namespace       = "kube-system"
  #   service_account = "karpenter"
  #   role_name       = "karpenter-${terraform.workspace}"
  # }

  iam_ack = {
    namespace       = "ack-system"
    service_account = "ack-iam-controller"
  }

  eks_ack = {
    namespace       = "ack-system"
    service_account = "ack-eks-controller"
  }
  
  ec2_ack = {
    namespace       = "ack-system"
    service_account = "ack-ec2-controller"
  }

  aws_addons = {
    enable_cert_manager                          = try(var.addons.enable_cert_manager, false)
    enable_aws_efs_csi_driver                    = try(var.addons.enable_aws_efs_csi_driver, false)
    enable_aws_fsx_csi_driver                    = try(var.addons.enable_aws_fsx_csi_driver, false)
    enable_aws_cloudwatch_metrics                = try(var.addons.enable_aws_cloudwatch_metrics, false)
    enable_aws_cloudwatch_observability          = try(var.addons.enable_aws_cloudwatch_observability, false)
    enable_aws_privateca_issuer                  = try(var.addons.enable_aws_privateca_issuer, false)
    enable_cluster_autoscaler                    = try(var.addons.enable_cluster_autoscaler, false)
    enable_external_dns                          = try(var.addons.enable_external_dns, false)
    enable_external_secrets                      = try(var.addons.enable_external_secrets, false)
    enable_aws_load_balancer_controller          = try(var.addons.enable_aws_load_balancer_controller, false)
    enable_fargate_fluentbit                     = try(var.addons.enable_fargate_fluentbit, false)
    enable_aws_for_fluentbit                     = try(var.addons.enable_aws_for_fluentbit, false)
    enable_aws_node_termination_handler          = try(var.addons.enable_aws_node_termination_handler, false)
    enable_karpenter                             = try(var.addons.enable_karpenter, false)
    enable_velero                                = try(var.addons.enable_velero, false)
    enable_aws_gateway_api_controller            = try(var.addons.enable_aws_gateway_api_controller, false)
    enable_aws_ebs_csi_resources                 = try(var.addons.enable_aws_ebs_csi_resources, false)
    enable_aws_secrets_store_csi_driver_provider = try(var.addons.enable_aws_secrets_store_csi_driver_provider, false)
    enable_ack_apigatewayv2                      = try(var.addons.enable_ack_apigatewayv2, false)
    enable_ack_dynamodb                          = try(var.addons.enable_ack_dynamodb, false)
    enable_ack_s3                                = try(var.addons.enable_ack_s3, false)
    enable_ack_rds                               = try(var.addons.enable_ack_rds, false)
    enable_ack_prometheusservice                 = try(var.addons.enable_ack_prometheusservice, false)
    enable_ack_emrcontainers                     = try(var.addons.enable_ack_emrcontainers, false)
    enable_ack_sfn                               = try(var.addons.enable_ack_sfn, false)
    enable_ack_eventbridge                       = try(var.addons.enable_ack_eventbridge, false)
    enable_aws_argocd                            = try(var.addons.enable_aws_argocd, false)
    enable_ack_iam                               = try(var.addons.enable_ack_iam, false)
    enable_ack_eks                               = try(var.addons.enable_ack_eks, false)
    enable_cni_metrics_helper                    = try(var.addons.enable_cni_metrics_helper, false)
    enable_ack_ec2                               = try(var.addons.enable_ack_ec2, false)
    enable_ack_efs                               = try(var.addons.enable_ack_efs, false)
    enable_kro                                   = try(var.addons.enable_kro, false)
    enable_kro_eks_rgs                           = try(var.addons.enable_kro_eks_rgs, false)
    enable_multi_acct                            = try(var.addons.enable_multi_acct, false)

  }
  oss_addons = {
    enable_argocd                          = try(var.addons.enable_argocd, false)
    enable_argo_rollouts                   = try(var.addons.enable_argo_rollouts, false)
    enable_argo_events                     = try(var.addons.enable_argo_events, false)
    enable_argo_workflows                  = try(var.addons.enable_argo_workflows, false)
    enable_cluster_proportional_autoscaler = try(var.addons.enable_cluster_proportional_autoscaler, false)
    enable_gatekeeper                      = try(var.addons.enable_gatekeeper, false)
    enable_gpu_operator                    = try(var.addons.enable_gpu_operator, false)
    enable_ingress_nginx                   = try(var.addons.enable_ingress_nginx, false)
    enable_keda                            = try(var.addons.enable_keda, false)
    enable_kyverno                         = try(var.addons.enable_kyverno, false)
    enable_kube_prometheus_stack           = try(var.addons.enable_kube_prometheus_stack, false)
    enable_metrics_server                  = try(var.addons.enable_metrics_server, false)
    enable_prometheus_adapter              = try(var.addons.enable_prometheus_adapter, false)
    enable_secrets_store_csi_driver        = try(var.addons.enable_secrets_store_csi_driver, false)
    enable_vpa                             = try(var.addons.enable_vpa, false)
  }

  addons = merge(
    local.aws_addons,
    local.oss_addons,
    { tenant = local.tenant },
    { fleet_member = local.fleet_member },
    { kubernetes_version = local.cluster_version },
    { aws_cluster_name = local.cluster_info.cluster_name },
  )

  addons_metadata = merge(
    {
      aws_cluster_name = local.cluster_info.cluster_name
      aws_region       = local.region
      aws_account_id   = module.eks-hub.account_id
      aws_vpc_id       = local.vpc_id
      use_ack          = local.use_ack
    },
    {
      argocd_namespace        = local.argocd_namespace,
      create_argocd_namespace = false,
      argocd_controller_role_arn = local.argocd_hub_pod_identity_iam_role_arn
    },
    {
      addons_repo_url      = local.gitops_addons_repo_url
      addons_repo_path     = var.gitops_addons_repo_path
      addons_repo_basepath = var.gitops_addons_repo_base_path
      addons_repo_revision = var.gitops_addons_repo_revision
    },
    {
      workload_repo_url      = local.gitops_workload_repo_url
      workload_repo_path     = var.gitops_workload_repo_path
      workload_repo_basepath = var.gitops_workload_repo_base_path
      workload_repo_revision = var.gitops_workload_repo_revision
    },
    {
      fleet_repo_url      = local.gitops_fleet_repo_url
      fleet_repo_path     = var.gitops_fleet_repo_path
      fleet_repo_basepath = var.gitops_fleet_repo_base_path
      fleet_repo_revision = var.gitops_fleet_repo_revision
    },
    {
      platform_repo_url      = local.gitops_platform_repo_url
      platform_repo_path     = var.gitops_platform_repo_path
      platform_repo_basepath = var.gitops_platform_repo_base_path
      platform_repo_revision = var.gitops_fleet_repo_revision
    },
    {
      external_secrets_namespace       = local.external_secrets.namespace
      external_secrets_service_account = local.external_secrets.service_account
    },
    {
      ack_iam_service_account = local.iam_ack.service_account
      ack_iam_namespace       = local.iam_ack.namespace
      ack_eks_service_account = local.eks_ack.service_account
      ack_eks_namespace       = local.eks_ack.namespace
      ack_ec2_service_account = local.ec2_ack.service_account
      ack_ec2_namespace       = local.ec2_ack.namespace
    },
    {
      aws_load_balancer_controller_namespace       = local.aws_load_balancer_controller.namespace
      aws_load_balancer_controller_service_account = local.aws_load_balancer_controller.service_account
    },
  )

  argocd_apps = {
    applicationsets = file("${path.module}/../bootstrap/applicationsets.yaml")
  }
  tags = merge(
    var.tags,
    {
      Blueprint  = local.name
      GithubRepo = "github.com/gitops-bridge-dev/gitops-bridge"
    }
  )
}