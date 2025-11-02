###############################################################################
# Unified Service Role Outputs (ACKs + Addons)
###############################################################################
output "service_roles" {
  description = "Map of all service role ARNs (created roles) by service name"
  value = {
    for k, v in module.service_role : k => {
      role_arn             = v.role_arn
      role_name            = v.role_name
      role_unique_id       = v.role_unique_id
      service_name         = v.service_name
      spoke_alias          = v.spoke_alias
      has_inline_policy    = try(module.service_policy[k].has_inline_policy, false)
      has_managed_policies = try(module.service_policy[k].has_managed_policies, false)
      managed_policy_arns  = try(module.service_policy[k].managed_policy_arns, {})
      source               = "spoke_created"
    }
  }
}

output "override_arns" {
  description = "Map of services using override ARNs (hub roles)"
  value = {
    for k, v in local.services_using_override : k => {
      role_arn     = lookup(v, "override_arn", "")
      service_name = k
      spoke_alias  = var.spoke_alias
      source       = "override"
    }
  }
}

output "all_service_roles" {
  description = "Combined map of all service roles (created + override)"
  value = merge(
    {
      for k, v in module.service_role : k => {
        role_arn     = v.role_arn
        service_name = k
        spoke_alias  = var.spoke_alias
        source       = "spoke_created"
      }
    },
    {
      for k, v in local.services_using_override : k => {
        role_arn     = lookup(v, "override_arn", "")
        service_name = k
        spoke_alias  = var.spoke_alias
        source       = "override"
      }
    }
  )
}

###############################################################################
# Separated outputs removed in favor of unified outputs
###############################################################################

###############################################################################
# ArgoCD ConfigMap Output
###############################################################################
output "argocd_configmap_name" {
  description = "Name of the ArgoCD ConfigMap created for this spoke"
  value       = try(module.argocd_configmap.config_map_name, "")
}

output "argocd_configmap_namespace" {
  description = "Namespace of the ArgoCD ConfigMap created for this spoke"
  value       = try(module.argocd_configmap.config_map_namespace, "")
}

###############################################################################
# Spoke Metadata
###############################################################################
output "spoke_alias" {
  description = "Alias of the spoke account"
  value       = var.spoke_alias
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = var.cluster_name
}

###############################################################################
# End of File
###############################################################################
