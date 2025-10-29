output "bindings" {
  description = "IAM binding IDs"
  value       = var.create ? google_project_iam_member.this[*].id : []
}
