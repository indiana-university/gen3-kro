variable "create" {
  description = "Whether to create EKS cluster resources"
  type        = bool
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
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
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Enable cluster creator admin permissions"
  type        = bool
}

variable "cluster_compute_config" {
  description = "Cluster compute configuration"
  type        = any
}

variable "tags" {
  description = "Tags to apply to all cluster resources"
  type        = map(string)
}

variable "region" {
  description = "AWS Region where the cluster is deployed"
  type        = string
}
