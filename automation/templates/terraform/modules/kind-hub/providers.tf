provider "kind" {
}

provider "kubernetes" {
  config_path = kind_cluster.dev.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = kind_cluster.dev.kubeconfig_path
  }
}