mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "444455556666"
      arn        = "arn:aws:iam::444455556666:user/mock"
      user_id    = "AIDAMOCK"
    }
  }
}

variables {
  cluster_name         = "test-csoc-cluster"
  csoc_source_role_arn = "arn:aws:iam::111122223333:role/test-ack-controller-role"
  spoke_alias          = "spoke1"
  roles = {
    ack-controller = {
      enabled          = true
      managed_policies = []
      custom_policies = [
        for index in range(9) : {
          Sid      = "AckStatement${index}"
          Effect   = "Allow"
          Action   = ["s3:ListAllMyBuckets"]
          Resource = ["*"]
        }
      ]
    }
    audit-reader = {
      enabled          = true
      managed_policies = []
      custom_policies = [
        for index in range(9) : {
          Sid      = "AuditStatement${index}"
          Effect   = "Allow"
          Action   = ["s3:ListAllMyBuckets"]
          Resource = ["*"]
        }
      ]
    }
  }
}

run "multiple_roles_have_unique_functional_names" {
  command = plan

  assert {
    condition = output.role_names == {
      ack-controller = "spoke1-ack-controller-access-role"
      audit-reader   = "spoke1-audit-reader-access-role"
    }
    error_message = "Every enabled spoke role must include its role key in its physical name."
  }

  assert {
    condition = (
      aws_iam_role_policy.custom_policies["ack-controller-0"].name == "spoke1-ack-controller-access-inline-00" &&
      aws_iam_role_policy.custom_policies["audit-reader-0"].name == "spoke1-audit-reader-access-inline-00" &&
      aws_iam_policy.custom_managed_policies["ack-controller-1"].name == "spoke1-ack-controller-access-managed-01" &&
      aws_iam_policy.custom_managed_policies["audit-reader-1"].name == "spoke1-audit-reader-access-managed-01"
    )
    error_message = "Inline and managed policy names must include the role key and chunk index."
  }
}

run "exact_manual_operator_principal" {
  command = plan

  variables {
    manual_operator_role_arns = [
      "arn:aws:iam::111122223333:role/test-csoc-operator-infrastructure-admin"
    ]
  }

  assert {
    condition     = strcontains(aws_iam_role.ack_workload["ack-controller"].assume_role_policy, "test-csoc-operator-infrastructure-admin")
    error_message = "The exact approved operator role ARN must appear in spoke trust."
  }

  assert {
    condition     = !strcontains(aws_iam_role.ack_workload["ack-controller"].assume_role_policy, ":root")
    error_message = "Spoke trust must not fall back to the CSOC account root."
  }
}
