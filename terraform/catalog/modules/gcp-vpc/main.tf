resource "google_compute_network" "this" {
  count = var.create ? 1 : 0

  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = var.routing_mode
}

resource "google_compute_subnetwork" "this" {
  count = var.create ? length(var.subnets) : 0

  name                     = var.subnets[count.index].subnet_name
  project                  = var.project_id
  region                   = var.subnets[count.index].subnet_region
  network                  = google_compute_network.this[0].id
  ip_cidr_range            = var.subnets[count.index].subnet_ip
  private_ip_google_access = var.subnets[count.index].subnet_private_access
}
