# Set region-wide variables

locals {
  region_config = yamldecode(file("region.yaml"))
  region = lookup(local.region_config, "region", "")
}
