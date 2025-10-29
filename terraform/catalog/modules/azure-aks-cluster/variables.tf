###############################################################################
# Azure AKS Cluster Module
# Creates an Azure Kubernetes Service cluster
###############################################################################

variable "create" {
  description = "Whether to create the AKS cluster"
  type        = bool
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for the cluster"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the AKS cluster"
  type        = string
}

variable "default_node_pool" {
  description = "Default node pool configuration"
  type = object({
    name       = string
    node_count = number
    vm_size    = string
  })
}

variable "network_plugin" {
  description = "Network plugin to use (azure or kubenet)"
  type        = string
}

variable "oidc_issuer_enabled" {
  description = "Enable OIDC issuer for workload identity"
  type        = bool
}

variable "workload_identity_enabled" {
  description = "Enable workload identity"
  type        = bool
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}
