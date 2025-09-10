terraform {
  required_version = ">= 1.2"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.0.19"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}
provider "kind" {
}
provider "kubernetes" {
  config_path = kind_cluster.dev.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = kind_cluster.dev.kubeconfig_path
  }
}