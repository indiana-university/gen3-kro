output "bindings" {
  description = "IAM binding IDs or service account email if override_id is set"
  value       = var.override_id != null ? [var.override_id] : (var.create ? google_project_iam_member.this[*].id : [])
}
