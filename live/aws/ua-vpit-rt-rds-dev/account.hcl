# Set account-wide variables
locals {
  account_config = yamldecode(file("account.yaml"))
  account_name = lookup(local.account_config, "account_name", "")
  profile    = lookup(local.account_config, "profile", "")
}
