###############################################################################
# Global Variables
###############################################################################
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

###############################################################################
# Network Variables
###############################################################################
variable "enable_vpc" {
  description = "Enable VPC creation"
  type        = bool
  default     = true
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = ""
}

###############################################################################
# GKE Variables
###############################################################################
variable "enable_gke_cluster" {
  description = "Enable GKE cluster creation"
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "latest"
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
