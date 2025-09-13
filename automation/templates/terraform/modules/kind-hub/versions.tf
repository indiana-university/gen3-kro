terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }

    kind = {
      source  = "tehcyx/kind"
      version = ">= 0.0.0"
    }
  }
}
