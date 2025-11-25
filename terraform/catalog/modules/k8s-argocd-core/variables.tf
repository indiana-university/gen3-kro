variable "create" {
  description = "Create terraform resources"
  type        = bool
}
variable "argocd" {
  description = "argocd helm options"
  type        = any
}
variable "install" {
  description = "Deploy argocd helm"
  type        = bool
}

variable "cluster" {
  description = "argocd cluster secret"
  type        = any
}

variable "apps" {
  description = "argocd app of apps to deploy"
  type        = any
}

variable "outputs_dir" {
  description = "Directory to store generated output files"
  type        = string
}
################################################################################
