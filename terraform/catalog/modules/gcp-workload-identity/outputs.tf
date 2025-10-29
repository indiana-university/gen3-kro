output "service_account_email" {
  description = "Email of the GCP service account"
  value       = var.create ? google_service_account.this[0].email : null
}

output "service_account_name" {
  description = "Name of the GCP service account"
  value       = var.create ? google_service_account.this[0].name : null
}

output "service_account_id" {
  description = "ID of the GCP service account"
  value       = var.create ? google_service_account.this[0].id : null
}
