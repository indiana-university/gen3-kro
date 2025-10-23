###############################################################################
# Global Variables
###############################################################################
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
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
  default     = "East US"
}

###############################################################################
# Network Variables
###############################################################################
variable "enable_vnet" {
  description = "Enable VNet creation"
  type        = bool
  default     = true
}

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
  default     = ""
}

variable "address_space" {
  description = "Address space for VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

###############################################################################
# AKS Variables
###############################################################################
variable "enable_aks_cluster" {
  description = "Enable AKS cluster creation"
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

###############################################################################
# Addon Configuration
###############################################################################
variable "addon_configs" {
  description = "Map of addon configurations"
  type        = any
  default     = {}
}

###############################################################################
# IAM Configuration
###############################################################################
variable "iam_base_path" {
  description = "Base path for IAM policy files"
  type        = string
  default     = "iam"
}

variable "iam_repo_root" {
  description = "Repository root path"
  type        = string
  default     = ""
}
