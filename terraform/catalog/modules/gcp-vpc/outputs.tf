output "network_id" {
  description = "ID of the VPC network"
  value       = var.create ? google_compute_network.this[0].id : null
}

output "network_name" {
  description = "Name of the VPC network"
  value       = var.create ? google_compute_network.this[0].name : null
}

output "subnet_ids" {
  description = "IDs of created subnets"
  value       = var.create ? google_compute_subnetwork.this[*].id : []
}

output "subnet_names" {
  description = "Names of created subnets"
  value       = var.create ? google_compute_subnetwork.this[*].name : []
}
