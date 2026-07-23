locals {
  repo_root    = get_repo_root()
  modules_path = "terraform/catalog/modules"
  units_path   = "${local.repo_root}/terraform/catalog/units"
  config       = jsondecode(file("${local.repo_root}/config/shared.auto.tfvars.json"))

  region          = lookup(local.config, "region", "us-east-1")
  profile         = lookup(local.config, "aws_profile", "")
  csoc_account_id = lookup(local.config, "csoc_account_id", "")
  csoc_alias      = lookup(local.config, "csoc_alias", "csoc")
  state_bucket    = lookup(local.config, "backend_bucket", "")
  backend_region  = lookup(local.config, "backend_region", local.region)
  spokes          = [for spoke in lookup(local.config, "spokes", []) : spoke if lookup(spoke, "enabled", false)]
  spoke_role_arns = [
    for spoke in local.spokes :
    "arn:aws:iam::${lookup(lookup(spoke, "provider", {}), "account_id", "")}:role/${spoke.alias}-ack-controller-access-role"
  ]

  operator_config = lookup(local.config, "aws_csoc_operator_iam", {})

  configured_users = lookup(local.operator_config, "users", {})
  users = {
    for user_key, user in local.configured_users : user_key => {
      name                      = lookup(user, "name", "")
      manage_virtual_mfa        = lookup(user, "manage_virtual_mfa", false)
      mfa_device_name           = lookup(user, "mfa_device_name", "${local.csoc_alias}-operator-${user_key}-mfa")
      attach_assume_role_policy = lookup(user, "attach_assume_role_policy", true)
      assume_role_policy_name   = lookup(user, "assume_role_policy_name", "")
    }
  }

  default_role_configs = {
    infrastructure-admin = {
      enabled                = true
      assigned_user_keys     = ["primary"]
      principal_arns         = []
      require_mfa            = true
      max_session_duration   = 43200
      policy_filename        = "infrastructure-admin.json"
      eks_access_policy_name = "AmazonEKSClusterAdminPolicy"
      allow_spoke_access     = true
    }
    platform-operator = {
      enabled                = false
      assigned_user_keys     = []
      principal_arns         = []
      require_mfa            = true
      max_session_duration   = 43200
      policy_filename        = "platform-operator.json"
      eks_access_policy_name = "AmazonEKSAdminPolicy"
      allow_spoke_access     = false
    }
  }
  role_configs = length(lookup(local.operator_config, "roles", {})) > 0 ? local.operator_config.roles : local.default_role_configs
  rendered_role_policies = {
    for role_key, role in local.role_configs : role_key => jsondecode(templatefile(
      "${local.repo_root}/iam/operator-roles/${lookup(role, "policy_filename", "${role_key}.json")}",
      {
        account_id           = local.csoc_account_id
        region               = local.region
        spoke_role_arns_json = jsonencode(local.spoke_role_arns)
      }
    ))
  }
  roles = {
    for role_key, role in local.role_configs : role_key => {
      enabled              = lookup(role, "enabled", true)
      name                 = lookup(role, "name", "${local.csoc_alias}-csoc-operator-${role_key}")
      assigned_user_keys   = lookup(role, "assigned_user_keys", [])
      principal_arns       = lookup(role, "principal_arns", [])
      require_mfa          = lookup(role, "require_mfa", true)
      max_session_duration = lookup(role, "max_session_duration", 43200)
      permissions_policy = jsonencode(merge(local.rendered_role_policies[role_key], {
        Statement = [
          for statement in local.rendered_role_policies[role_key].Statement : statement
          if try(statement.Sid, "") != "STSAssumeRoleCrossAccount" || length(local.spoke_role_arns) > 0
        ]
      }))
      eks_access_policy_arn = lookup(role, "eks_access_policy_name", "") != "" ? "arn:aws:eks::aws:cluster-access-policy/${role.eks_access_policy_name}" : ""
      allow_spoke_access    = lookup(role, "allow_spoke_access", false)
    }
  }

  tags = merge(
    {
      Terraform = "true"
      ManagedBy = "terragrunt"
      Module    = "aws-csoc-operator-iam"
      Stack     = "operators-iam"
    },
    lookup(local.config, "tags", {})
  )
}

unit "aws_csoc_operator_iam" {
  source = "${local.units_path}/aws-csoc-operator-iam"
  path   = "aws-csoc-operator-iam"

  values = {
    modules_path = local.modules_path
    profile      = local.profile
    region       = local.region

    state_bucket   = local.state_bucket
    backend_region = local.backend_region
    state_key      = "prereq/aws-csoc-operator-iam/terraform.tfstate"

    users            = local.users
    roles            = local.roles
    default_role_key = lookup(local.operator_config, "default_role_key", "infrastructure-admin")
    tags             = local.tags
  }
}
