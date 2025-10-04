provider "kubernetes" {
  host                   = local.cluster_info == null ? module.kind-hub.endpoint                                         : local.cluster_info.cluster_endpoint
  cluster_ca_certificate = local.cluster_info == null ? base64decode(module.kind-hub.credentials.cluster_ca_certificate) : base64decode(local.cluster_info.cluster_certificate_authority_data)
  client_certificate     = local.cluster_info == null ? base64decode(module.kind-hub.credentials.client_certificate)     : null
  client_key             = local.cluster_info == null ? base64decode(module.kind-hub.credentials.client_key)             : null
  token                  = local.cluster_info == null ? null                                                             : module.eks-hub.token
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_info == null ? module.kind-hub.endpoint                           : local.cluster_info.cluster_endpoint
    cluster_ca_certificate = local.cluster_info == null ? module.kind-hub.credentials.cluster_ca_certificate : base64decode(local.cluster_info.cluster_certificate_authority_data)
    client_certificate     = local.cluster_info == null ? module.kind-hub.credentials.client_certificate     : null
    client_key             = local.cluster_info == null ? module.kind-hub.credentials.client_key             : null
    token                  = local.cluster_info == null ? null                                               : module.eks-hub.token

  }
}

provider "aws" {
#  region   = local.hub_region
 profile  = "boadeyem_tf"

  alias   = "hub"
}
