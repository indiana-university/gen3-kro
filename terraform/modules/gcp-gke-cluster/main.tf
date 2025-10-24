resource "google_container_cluster" "this" {
  count = var.create ? 1 : 0

  name     = var.cluster_name
  project  = var.project_id
  location = var.location

  network    = var.network
  subnetwork = var.subnetwork

  min_master_version = var.kubernetes_version == "latest" ? null : var.kubernetes_version

  # Enable workload identity
  workload_identity_config {
    workload_pool = var.workload_identity_enabled ? "${var.project_id}.svc.id.goog" : null
  }

  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  resource_labels = var.tags
}

resource "google_container_node_pool" "this" {
  count = var.create ? length(var.node_pools) : 0

  name     = var.node_pools[count.index].name
  project  = var.project_id
  location = var.location
  cluster  = google_container_cluster.this[0].name

  autoscaling {
    min_node_count = var.node_pools[count.index].min_count
    max_node_count = var.node_pools[count.index].max_count
  }

  node_config {
    machine_type = var.node_pools[count.index].machine_type
    disk_size_gb = var.node_pools[count.index].disk_size_gb

    workload_metadata_config {
      mode = var.workload_identity_enabled ? "GKE_METADATA" : "GCE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}
