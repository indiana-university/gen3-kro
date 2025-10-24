resource "google_service_account" "this" {
  count = var.create ? 1 : 0

  account_id   = var.service_account_name
  project      = var.project_id
  display_name = "Service account for ${var.service_account_name}"
}

resource "google_service_account_iam_member" "workload_identity" {
  count = var.create ? 1 : 0

  service_account_id = google_service_account.this[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.service_account_k8s}]"
}

resource "google_project_iam_member" "this" {
  count = var.create ? length(var.roles) : 0

  project = var.project_id
  role    = var.roles[count.index]
  member  = "serviceAccount:${google_service_account.this[0].email}"
}

resource "google_project_iam_member" "custom_role" {
  count = var.create && var.custom_role_id != null ? 1 : 0

  project = var.project_id
  role    = "projects/${var.project_id}/roles/${var.custom_role_id}"
  member  = "serviceAccount:${google_service_account.this[0].email}"
}
