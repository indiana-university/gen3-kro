###################################################################################################################################################
# Generic Spoke Role Module
# Creates IAM role in spoke account that can be assumed by pod identity from hub
# Supports both ACK controllers and addons
###################################################################################################################################################

###################################################################################################################################################
# Spoke Account - IAM Role for Cross-Account Access
###################################################################################################################################################
resource "aws_iam_role" "spoke" {
  count = var.override_id == null && var.create ? 1 : 0

  # Role name format (unified): {spoke_alias}-{service_name}-spoke-role
  name = "${var.spoke_alias}-${var.service_name}-spoke-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = var.csoc_pod_identity_role_arn
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  description = "Spoke role for ${var.cluster_name} ${var.service_name} in Spoke: ${var.spoke_alias}"
  tags        = var.tags
}

###############################################################################
# Attach Inline Policy to Spoke Role
###############################################################################
resource "aws_iam_role_policy" "spoke_inline" {
  count = var.override_id == null && var.create ? 1 : 0

  name = "${var.service_name}-policy"
  role = aws_iam_role.spoke[0].name

  policy = var.combined_policy_json != null ? var.combined_policy_json : jsonencode({
    Version   = "2012-10-17"
    Statement = []
  })
}
