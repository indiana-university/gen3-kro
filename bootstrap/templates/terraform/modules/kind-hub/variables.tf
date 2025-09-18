variable "cluster_name" {
  description = "Name of the Kind cluster"
  type        = string
  default     = "kftray-cluster"
  nullable = true
}

variable "kubernetes_version" {
  description = "Version of the Kind node image"
  type        = string
  default     = "v1.30.4"
  nullable    = true
}

variable "kubeconfig_dir" {
  description = "Directory to store the kubeconfig file"
  type        = string
  default     = "~/.kube"
  nullable    = true
}