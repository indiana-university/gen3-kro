mock_provider "aws" {
  mock_data "aws_iam_user" {
    defaults = {
      arn = "arn:aws:iam::111122223333:user/mock-operator"
    }
  }
}

variables {
  users = {
    primary = {
      name = "mock-operator"
    }
  }
  roles = {
    infrastructure-admin = {
      name                  = "test-csoc-operator-infrastructure-admin"
      assigned_user_keys    = ["primary"]
      permissions_policy    = jsonencode({ Version = "2012-10-17", Statement = [] })
      eks_access_policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      allow_spoke_access    = true
    }
    platform-operator = {
      enabled               = false
      name                  = "test-csoc-operator-platform-operator"
      assigned_user_keys    = []
      permissions_policy    = jsonencode({ Version = "2012-10-17", Statement = [] })
      eks_access_policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
    }
  }
}

run "one_user_one_enabled_role" {
  command = plan

  assert {
    condition     = output.role_names == { infrastructure-admin = "test-csoc-operator-infrastructure-admin" }
    error_message = "Only the enabled infrastructure-admin role should be planned."
  }

  assert {
    condition     = length(output.user_role_arns.primary) == 1
    error_message = "The primary user should receive exactly one role assignment."
  }

  assert {
    condition     = length(output.spoke_access_role_arns) == 1
    error_message = "Only the approved infrastructure-admin role should be exported for spoke access."
  }
}

run "one_user_multiple_roles" {
  command = plan

  variables {
    roles = {
      infrastructure-admin = {
        name               = "test-csoc-operator-infrastructure-admin"
        assigned_user_keys = ["primary"]
        permissions_policy = jsonencode({ Version = "2012-10-17", Statement = [] })
      }
      platform-operator = {
        name               = "test-csoc-operator-platform-operator"
        assigned_user_keys = ["primary"]
        permissions_policy = jsonencode({ Version = "2012-10-17", Statement = [] })
      }
    }
  }

  assert {
    condition     = length(output.user_role_arns.primary) == 2
    error_message = "A user assigned to two roles should receive both role ARNs."
  }
}

run "users_assigned_to_different_roles" {
  command = plan

  variables {
    users = {
      primary = {
        name = "mock-infrastructure-operator"
      }
      secondary = {
        name = "mock-platform-operator"
      }
    }
    roles = {
      infrastructure-admin = {
        name               = "test-csoc-operator-infrastructure-admin"
        assigned_user_keys = ["primary"]
        permissions_policy = jsonencode({ Version = "2012-10-17", Statement = [] })
      }
      platform-operator = {
        name               = "test-csoc-operator-platform-operator"
        assigned_user_keys = ["secondary"]
        permissions_policy = jsonencode({ Version = "2012-10-17", Statement = [] })
      }
    }
  }

  assert {
    condition     = length(output.user_role_arns.primary) == 1 && length(output.user_role_arns.secondary) == 1
    error_message = "Each user should receive only the role assigned to that user."
  }

}

run "mfa_required_trust_is_exact" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_role.operator["infrastructure-admin"].assume_role_policy, "aws:MultiFactorAuthPresent")
    error_message = "Human role trust must require MFA."
  }

  assert {
    condition     = !strcontains(aws_iam_role.operator["infrastructure-admin"].assume_role_policy, ":root")
    error_message = "Operator role trust must not contain an account-root fallback."
  }
}

run "reject_unknown_user_assignment" {
  command = plan

  variables {
    roles = {
      infrastructure-admin = {
        name               = "test-csoc-operator-infrastructure-admin"
        assigned_user_keys = ["missing"]
        permissions_policy = jsonencode({ Version = "2012-10-17", Statement = [] })
      }
    }
  }

  expect_failures = [var.roles]
}

run "reject_malformed_policy" {
  command = plan

  variables {
    roles = {
      infrastructure-admin = {
        name               = "test-csoc-operator-infrastructure-admin"
        assigned_user_keys = ["primary"]
        permissions_policy = "not-json"
      }
    }
  }

  expect_failures = [var.roles]
}

run "reject_invalid_session_duration" {
  command = plan

  variables {
    roles = {
      infrastructure-admin = {
        name                 = "test-csoc-operator-infrastructure-admin"
        assigned_user_keys   = ["primary"]
        max_session_duration = 900
        permissions_policy   = jsonencode({ Version = "2012-10-17", Statement = [] })
      }
    }
  }

  expect_failures = [var.roles]
}

run "reject_enabled_role_without_principal" {
  command = plan

  variables {
    roles = {
      infrastructure-admin = {
        name               = "test-csoc-operator-infrastructure-admin"
        assigned_user_keys = []
        principal_arns     = []
        permissions_policy = jsonencode({ Version = "2012-10-17", Statement = [] })
      }
    }
  }

  expect_failures = [var.roles]
}
