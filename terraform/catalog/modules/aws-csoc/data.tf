data "aws_region" "current" {}

# CSOC account identity - retrieved from aws_profile
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# OIDC provider for IRSA trust (shared ACK role + optional ArgoCD role)
