variable "create" {
  description = "Whether to create EKS cluster resources"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = true
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Enable cluster creator admin permissions"
  type        = bool
  default     = true
}

variable "cluster_compute_config" {
  description = "Cluster compute configuration"
  type        = any
  default = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }
}

variable "cluster_addons" {
  description = "Map of EKS cluster addon configurations (e.g., eks-pod-identity-agent, vpc-cni, etc.)"
  type        = any
  default     = {}
}

variable "tags" {
  description = "Tags to apply to all cluster resources"
  type        = map(string)
  default     = {}
}
