output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.resource_group.resource_group_name
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks_cluster.cluster_name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL"
  value       = module.aks_cluster.oidc_issuer_url
}

output "managed_identities" {
  description = "Managed identity details"
  value = {
    for k, v in module.managed_identities : k => {
      client_id    = v.client_id
      principal_id = v.principal_id
    }
  }
}
