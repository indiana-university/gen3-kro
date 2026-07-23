locals {
  name            = var.csoc_alias
  vpc_cidr        = var.vpc_cidr
  cluster_name    = "${local.name}-csoc-cluster"
  vpc_name        = "${local.name}-csoc-vpc"
  azs             = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)
  cluster_version = var.kubernetes_version

  tags = merge(
    {
      Blueprint   = local.name
      Environment = var.environment
      Module      = "aws-csoc-cluster"
    },
    var.tags
  )
}
