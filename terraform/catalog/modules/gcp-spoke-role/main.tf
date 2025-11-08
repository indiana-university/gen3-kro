resource "google_project_iam_member" "this" {
  count = var.override_id == null && var.create ? length(var.roles) : 0

  project = var.project_id
  role    = var.roles[count.index]
  member  = "serviceAccount:${var.csoc_service_account_email}"
}

resource "google_project_iam_member" "custom_role" {
  count = var.override_id == null && var.create && var.custom_role_id != "" ? 1 : 0

  project = var.project_id
  role    = "projects/${var.project_id}/roles/${var.custom_role_id}"
  member  = "serviceAccount:${var.csoc_service_account_email}"
}
