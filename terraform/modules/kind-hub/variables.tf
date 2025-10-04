variable "cluster_name" {
  description = "Name of the Kind cluster"
  type        = string
  default     = "kftray-cluster"
}

variable "kubernetes_version" {
  description = "Version of the Kind node image"
  type        = string
  default     = "v1.30.4"
}

variable "kubeconfig_dir" {
  description = "Directory to store the kubeconfig file"
  type        = string
  default     = "root"
}

variable "create" {
  description = "Whether to create the Kind cluster"
  type        = bool
  default     = true
}