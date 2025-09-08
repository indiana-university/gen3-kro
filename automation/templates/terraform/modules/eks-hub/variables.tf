variable "vpc_name" {
  description = "VPC name to be used by pipelines for data"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "addons" {
  description = "Kubernetes addons"
  type        = any
  default     = {
    enable_metrics_server               = true
    enable_kyverno                      = true
    enable_kyverno_policies             = true
    enable_kyverno_policy_reporter      = true
    enable_argocd                       = true
    enable_cni_metrics_helper           = false
    enable_kube_state_metrics           = true
    enable_cert_manager                 = false
    enable_external_dns                 = false
    enable_external_secrets             = true
    enable_ack_iam                      = true
    enable_ack_eks                      = true
    enable_ack_ec2                      = true
    enable_ack_efs                      = true
    enable_kro                          = true
    enable_kro_eks_rgs                  = true
    enable_multi_acct                   = true
  }
}

variable "manifests" {
  description = "Kubernetes manifests"
  type        = any
  default     = {}
}

variable "enable_addon_selector" {
  description = "select addons using cluster selector"
  type        = bool
  default     = false
}

variable "route53_zone_name" {
  description = "The route53 zone for external dns"
  default     = ""
}

variable "ackCreate" {
  description = "Creating PodIdentity and addons relevant resources with ACK"
  default     = false
}

variable "enable_efs" {
  description = "Enabling EFS file system"
  type        = bool
  default     = false
}

variable "enable_automode" {
  description = "Enabling Automode Cluster"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
  default     = "hub-cluster"
}

variable "use_ack" {
  description = "Defining to use ack or terraform for pod identity if this is true then we will use this label to deploy resouces with ack"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Name of the environment for the Hub Cluster"
  type        = string
  default     = "control-plane"
}

variable "tenant" {
  description = "Name of the tenant for the Hub Cluster"
  type        = string
  default     = "control-plane"
}

variable "account_ids" {
  description = "List of aws accounts ACK will need to connect to"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region where the cluster is deployed"
  type        = string
  default     = "us-east-1"
}

variable "gitops_addons_app_private_key_ssm_path" {
  description = "SSM path for the GitOps Addons app private key"
  type        = string
  default     = "/kro/gitops/addons/app-private-key"
}

variable "gitops_fleet_app_private_key_ssm_path" {
  description = "SSM path for the GitOps Fleet app private key"
  type        = string
  default     = "/kro/gitops/fleet/app-private-key"
}

variable "gitops_workload_app_private_key_ssm_path" {
  description = "SSM path for the GitOps Workload app private key"
  type        = string
  default     = "/kro/gitops/workload/app-private-key"
}

variable "gitops_platform_app_private_key_ssm_path" {
  description = "SSM path for the GitOps Platform app private key"
  type        = string
  default     = "/kro/gitops/platform/app-private-key"
}

# Define variables for the policy URLs
variable "policy_arn_urls" {
  type    = map(string)
  default = {
    iam = "https://raw.githubusercontent.com/aws-controllers-k8s/iam-controller/main/config/iam/recommended-policy-arn"
    ec2 = "https://raw.githubusercontent.com/aws-controllers-k8s/ec2-controller/main/config/iam/recommended-policy-arn"
    eks = "https://raw.githubusercontent.com/aws-controllers-k8s/eks-controller/main/config/iam/recommended-policy-arn"
  }
}

variable "inline_policy_urls" {
  type    = map(string)
  default = {
    iam = "https://raw.githubusercontent.com/aws-controllers-k8s/iam-controller/main/config/iam/recommended-inline-policy"
    ec2 = "https://raw.githubusercontent.com/aws-controllers-k8s/ec2-controller/main/config/iam/recommended-inline-policy"
    eks = "https://raw.githubusercontent.com/aws-controllers-k8s/eks-controller/main/config/iam/recommended-inline-policy"
  }
}
variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default     = {}
}

variable "name" {
  description = "Generic name for items in this module"
  type        = string
}

variable "cluster_info" {
  description = "Cluster information to be used by the module"
  type        = any
  default     = {}
}

variable "private_key_paths" {
  description = "List of SSM parameter paths for private keys"
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.21"
}

variable "valid_policies" {
  description = "Map of valid policy ARNs"
  type        = any
  default     = {}
}

variable "aws_addons" {
  description = "AWS Addons configuration"
  type = any
  default = {}
}

variable "external_secrets" {
  description = "External Secrets configuration"
  type = any
  default = {}
}

variable "aws_load_balancer_controller" {
  description = "AWS Load Balancer Controller configuration"
  type = any
  default = {}
}