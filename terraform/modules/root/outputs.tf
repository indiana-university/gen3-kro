# Basic cluster outputs for scripts
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = local.cluster_name
}

output "aws_region" {
  description = "AWS region where the Hub Cluster is deployed"
  value       = var.hub_aws_region
}

output "aws_profile" {
  description = "AWS CLI profile used"
  value       = var.aws_profile
}

output "old_cluster_name" {
  description = "Previous cluster name (if performing migration)"
  value       = local.old_cluster_name
}

output "argo_metadata_yaml" {
  description = "Argo metadata annotations used by the cluster (YAML)"
  value       = yamlencode(local.addons_metadata)
}

output "ack_controllers_flat_annotations" {
  description = "ACK controllers metadata (flattened annotations)"
  value = {
    for k, v in local.addons_metadata :
    k => v if startswith(k, "ack_")
  }
}
