###################################################################################################################################################
# EKS Addons Pod Identities Module (Addons Only - No ACK)
# Consolidates pod identity configurations for Kubernetes addons
###################################################################################################################################################

###################################################################################################################################################
# Amazon Managed Service for Prometheus Pod Identity
###################################################################################################################################################
module "amazon_managed_service_prometheus_pod_identity" {
  count = var.create && var.enable_amazon_managed_service_prometheus ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-amazon-managed-service-prometheus"

  attach_amazon_managed_service_prometheus_policy  = true
  amazon_managed_service_prometheus_workspace_arns = var.amazon_managed_service_prometheus_workspace_arns

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.amazon_managed_service_prometheus_namespace
      service_account = var.amazon_managed_service_prometheus_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# ArgoCD Hub Pod Identity
###################################################################################################################################################
module "argocd_hub_pod_identity" {
  count = var.create && var.enable_argocd ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name            = "${var.cluster_name}-argocd-hub-mgmt"
  use_name_prefix = false

  attach_custom_policy = true
  policy_statements = [
    {
      sid       = "ArgoCD"
      actions   = ["sts:AssumeRole", "sts:TagSession"]
      resources = ["*"]
    }
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

  tags = var.tags
}

###################################################################################################################################################
# AWS AppMesh Controller Pod Identity
###################################################################################################################################################
module "aws_appmesh_controller_pod_identity" {
  count = var.create && var.enable_aws_appmesh_controller ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-appmesh-controller"

  attach_aws_appmesh_controller_policy = true

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.aws_appmesh_controller_namespace
      service_account = var.aws_appmesh_controller_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS AppMesh Envoy Proxy Pod Identity
###################################################################################################################################################
module "aws_appmesh_envoy_proxy_pod_identity" {
  count = var.create && var.enable_aws_appmesh_envoy_proxy ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-appmesh-envoy-proxy"

  attach_aws_appmesh_envoy_proxy_policy = true

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.aws_appmesh_envoy_proxy_namespace
      service_account = var.aws_appmesh_envoy_proxy_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS CloudWatch Observability Pod Identity
###################################################################################################################################################
module "aws_cloudwatch_observability_pod_identity" {
  count = var.create && var.enable_aws_cloudwatch_observability ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-cloudwatch-observability"

  attach_aws_cloudwatch_observability_policy = true

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.aws_cloudwatch_observability_namespace
      service_account = var.aws_cloudwatch_observability_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# EBS CSI Pod Identity
###################################################################################################################################################
module "aws_ebs_csi_pod_identity" {
  count = var.create && var.enable_aws_ebs_csi ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-ebs-csi"

  attach_aws_ebs_csi_policy = true
  aws_ebs_csi_kms_arns      = var.ebs_csi_kms_arns

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.ebs_csi_namespace
      service_account = var.ebs_csi_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS EFS CSI Driver Pod Identity
###################################################################################################################################################
module "aws_efs_csi_pod_identity" {
  count = var.create && var.enable_aws_efs_csi ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-efs-csi"

  attach_aws_efs_csi_policy = true

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.aws_efs_csi_namespace
      service_account = var.aws_efs_csi_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS FSx for Lustre CSI Driver Pod Identity
###################################################################################################################################################
module "aws_fsx_lustre_csi_pod_identity" {
  count = var.create && var.enable_aws_fsx_lustre_csi ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-fsx-lustre-csi"

  attach_aws_fsx_lustre_csi_policy     = true
  aws_fsx_lustre_csi_service_role_arns = var.aws_fsx_lustre_csi_service_role_arns

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.aws_fsx_lustre_csi_namespace
      service_account = var.aws_fsx_lustre_csi_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS Gateway Controller Pod Identity
###################################################################################################################################################
module "aws_gateway_controller_pod_identity" {
  count = var.create && var.enable_aws_gateway_controller ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-gateway-controller"

  attach_aws_gateway_controller_policy = true

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.aws_gateway_controller_namespace
      service_account = var.aws_gateway_controller_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS Load Balancer Controller Pod Identity
###################################################################################################################################################
module "aws_lb_controller_pod_identity" {
  count = var.create && var.enable_aws_load_balancer_controller ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-lbc"

  attach_aws_lb_controller_policy = true

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.aws_load_balancer_controller_namespace
      service_account = var.aws_load_balancer_controller_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS Load Balancer Controller - Target Group Binding Only Pod Identity
###################################################################################################################################################
module "aws_lb_controller_targetgroup_binding_only_pod_identity" {
  count = var.create && var.enable_aws_lb_controller_targetgroup_binding_only ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-lbc-targetgroup-binding-only"

  attach_aws_lb_controller_targetgroup_binding_only_policy = true
  aws_lb_controller_targetgroup_arns                       = var.aws_lb_controller_targetgroup_arns

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.aws_lb_controller_targetgroup_binding_only_namespace
      service_account = var.aws_lb_controller_targetgroup_binding_only_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS Node Termination Handler Pod Identity
###################################################################################################################################################
module "aws_node_termination_handler_pod_identity" {
  count = var.create && var.enable_aws_node_termination_handler ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-node-termination-handler"

  attach_aws_node_termination_handler_policy  = true
  aws_node_termination_handler_sqs_queue_arns = var.aws_node_termination_handler_sqs_queue_arns

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.aws_node_termination_handler_namespace
      service_account = var.aws_node_termination_handler_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS Private CA Issuer Pod Identity
###################################################################################################################################################
module "aws_privateca_issuer_pod_identity" {
  count = var.create && var.enable_aws_privateca_issuer ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-privateca-issuer"

  attach_aws_privateca_issuer_policy = true
  aws_privateca_issuer_acmca_arns    = var.aws_privateca_issuer_acmca_arns

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.aws_privateca_issuer_namespace
      service_account = var.aws_privateca_issuer_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS VPC CNI - IPv4 Pod Identity
###################################################################################################################################################
module "aws_vpc_cni_ipv4_pod_identity" {
  count = var.create && var.enable_aws_vpc_cni_ipv4 ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-vpc-cni-ipv4"

  attach_aws_vpc_cni_policy = true
  aws_vpc_cni_enable_ipv4   = true

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.aws_vpc_cni_ipv4_namespace
      service_account = var.aws_vpc_cni_ipv4_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS VPC CNI - IPv6 Pod Identity
###################################################################################################################################################
module "aws_vpc_cni_ipv6_pod_identity" {
  count = var.create && var.enable_aws_vpc_cni_ipv6 ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-vpc-cni-ipv6"

  attach_aws_vpc_cni_policy = true
  aws_vpc_cni_enable_ipv6   = true

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.aws_vpc_cni_ipv6_namespace
      service_account = var.aws_vpc_cni_ipv6_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# Cert Manager Pod Identity
###################################################################################################################################################
module "cert_manager_pod_identity" {
  count = var.create && var.enable_cert_manager ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-cert-manager"

  attach_cert_manager_policy    = true
  cert_manager_hosted_zone_arns = var.cert_manager_hosted_zone_arns

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.cert_manager_namespace
      service_account = var.cert_manager_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# Cluster Autoscaler Pod Identity
###################################################################################################################################################
module "cluster_autoscaler_pod_identity" {
  count = var.create && var.enable_cluster_autoscaler ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-cluster-autoscaler"

  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = var.cluster_autoscaler_cluster_names

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.cluster_autoscaler_namespace
      service_account = var.cluster_autoscaler_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# External DNS Pod Identity
###################################################################################################################################################
module "external_dns_pod_identity" {
  count = var.create && var.enable_external_dns ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-external-dns"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = var.external_dns_hosted_zone_arns

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.external_dns_namespace
      service_account = var.external_dns_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# External Secrets Pod Identity
###################################################################################################################################################
module "external_secrets_pod_identity" {
  count = var.create && var.enable_external_secrets ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-external-secrets"

  attach_external_secrets_policy        = true
  external_secrets_kms_key_arns         = var.external_secrets_kms_key_arns
  external_secrets_secrets_manager_arns = var.external_secrets_secrets_manager_arns
  external_secrets_ssm_parameter_arns   = var.external_secrets_ssm_parameter_arns
  external_secrets_create_permission    = var.external_secrets_create_permission

  attach_custom_policy = var.external_secrets_attach_custom_policy
  policy_statements    = var.external_secrets_policy_statements

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.external_secrets_namespace
      service_account = var.external_secrets_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# Mountpoint S3 CSI Driver Pod Identity
###################################################################################################################################################
module "mountpoint_s3_csi_pod_identity" {
  count = var.create && var.enable_mountpoint_s3_csi ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-mountpoint-s3-csi"

  attach_mountpoint_s3_csi_policy    = true
  mountpoint_s3_csi_bucket_arns      = var.mountpoint_s3_csi_bucket_arns
  mountpoint_s3_csi_bucket_path_arns = var.mountpoint_s3_csi_bucket_path_arns

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.mountpoint_s3_csi_namespace
      service_account = var.mountpoint_s3_csi_service_account
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# Velero Pod Identity
###################################################################################################################################################
module "velero_pod_identity" {
  count = var.create && var.enable_velero ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-velero"

  attach_velero_policy       = true
  velero_s3_bucket_arns      = var.velero_s3_bucket_arns
  velero_s3_bucket_path_arns = var.velero_s3_bucket_path_arns

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = var.velero_namespace
      service_account = var.velero_service_account
    }
  }

  tags = var.tags
}
