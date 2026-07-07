################################################################################
# AWS Provider — inherited by child modules for AWS API calls
#
# The kubernetes and helm providers are NOT defined here. In-cluster bootstrap
# modules configure them using the cluster endpoint and exec-based auth.
################################################################################

provider "aws" {
  profile = var.aws_profile
  region  = var.region
}
