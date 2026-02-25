################################################################################
# AWS Provider — inherited by child modules for AWS API calls
#
# The kubernetes and helm providers are NOT defined here. Each catalog module
# (aws-csoc, argocd-bootstrap) configures its own kubernetes/helm provider
# internally using the cluster endpoint and exec-based auth.
################################################################################

provider "aws" {
  region = var.region
}
