###################################################################################################################################################
# Generic Spoke Role Module
# Creates IAM role in spoke account that can be assumed by pod identity from hub
# Supports both ACK controllers and addons
###################################################################################################################################################

###################################################################################################################################################
# Spoke Account - IAM Role for Cross-Account Access
###################################################################################################################################################
resource "aws_iam_role" "spoke" {
  count    = var.create ? 1 : 0

  # Role name format (unified): {spoke_alias}-{service_name}-spoke-role
  name = "${var.spoke_alias}-${var.service_name}-spoke-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = var.hub_pod_identity_role_arn
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  description = "Spoke role for ${var.cluster_name} ${var.service_name} in Spoke: ${var.spoke_alias}"
  tags        = var.tags
}

###################################################################################################################################################
# Attach Inline Policy to Spoke Role
# Always created when var.create is true; uses provided policy or empty policy if none provided
# This avoids "known only after apply" issues with conditional count
###################################################################################################################################################
resource "aws_iam_role_policy" "spoke_inline" {
  count = var.create ? 1 : 0

  # Inline policy name (unified): {service_name}-policy
  name = "${var.service_name}-policy"
  role = aws_iam_role.spoke[0].name

  # Use provided policy JSON or create minimal no-op policy if none provided
  policy = var.combined_policy_json != null ? var.combined_policy_json : jsonencode({
    Version = "2012-10-17"
    Statement = []
  })
}

###################################################################################################################################################
# Attach Managed Policies to Spoke Role
# Note: Managed policy ARNs from filesystem are unknown at plan time, causing for_each issues.
# For ACK controllers, inline policies contain all necessary permissions, so managed policies
# are typically not used. If needed, they should be pre-defined in variables, not loaded from filesystem.
###################################################################################################################################################
# Disabled: Managed policy attachment removed due to "known only after apply" limitation
# If managed policies are required, they should be defined statically in terragrunt inputs
# rather than loaded dynamically from filesystem in the iam-policy module
