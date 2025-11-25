###############################################################################
# IAM Policy Module (Cloud Agnostic)
# Accepts policy content directly and provides it to consumers
# Replaces placeholders with actual account/project/subscription IDs
###############################################################################

###############################################################################
# Local Variables
###############################################################################
locals {
  # Determine if policy is actually provided
  has_inline_policy = var.policy_inline_json != null && var.policy_inline_json != ""

  # Replace placeholders in policy documents
  # AWS: <ACCOUNT_ID>, <CSOC_ACCOUNT_ID>
  # Azure: <SUBSCRIPTION_ID>, <TENANT_ID>
  # GCP: <PROJECT_ID>, <PROJECT_NUMBER>
  policy_with_replacements = local.has_inline_policy ? replace(
    replace(
      replace(
        replace(
          replace(
            replace(
              var.policy_inline_json,
              "<ACCOUNT_ID>", var.account_id != null ? var.account_id : "<ACCOUNT_ID>"
            ),
            "<CSOC_ACCOUNT_ID>", var.csoc_account_id != null ? var.csoc_account_id : "<CSOC_ACCOUNT_ID>"
          ),
          "<SUBSCRIPTION_ID>", var.subscription_id != null ? var.subscription_id : "<SUBSCRIPTION_ID>"
        ),
        "<TENANT_ID>", var.tenant_id != null ? var.tenant_id : "<TENANT_ID>"
      ),
      "<PROJECT_ID>", var.project_id != null ? var.project_id : "<PROJECT_ID>"
    ),
    "<PROJECT_NUMBER>", var.project_number != null ? var.project_number : "<PROJECT_NUMBER>"
  ) : null
}

###############################################################################
# End of File
###############################################################################
