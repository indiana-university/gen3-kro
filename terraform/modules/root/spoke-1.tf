provider "aws" {
  alias   = "spoke1"
  # region  = "us-east-1"
  profile = "boadeyem_tf"
}

module "spoke1" {
  source = "../iam-access"

  ack_services        = var.ack_services
  environment         = var.environment
  hub_account_id      = local.hub_account_id
  cluster_info        = local.cluster_info
  ack_services_config = local.ack_services_config
  tags                = var.tags

  providers = {
    aws.hub   = aws.hub
    aws.spoke = aws.spoke1
  }
}
