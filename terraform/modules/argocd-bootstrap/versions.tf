terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.2"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}
