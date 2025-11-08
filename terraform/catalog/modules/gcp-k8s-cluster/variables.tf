###############################################################################
# GCP GKE Cluster Module
# Creates a Google Kubernetes Engine cluster
###############################################################################

variable "create" {
  description = "Whether to create the GKE cluster"
  type        = bool
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "location" {
  description = "GCP region or zone"
  type        = string
}

variable "network" {
  description = "VPC network name"
  type        = string
}

variable "subnetwork" {
  description = "Subnetwork name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
}

variable "node_pools" {
  description = "Node pool configurations"
  type = list(object({
    name         = string
    machine_type = string
    min_count    = number
    max_count    = number
    disk_size_gb = number
  }))
}

variable "workload_identity_enabled" {
  description = "Enable workload identity"
  type        = bool
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}
