#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Data Sources
#-------------------------------------------------------------------------------------------------------------------------------------------------#
data "aws_caller_identity" "spoke" {
  provider = aws.spoke
}

locals {
  # Use the enable flags from variables (calculated in Terragrunt)
  enable_external_spoke = var.enable_external_spoke
  enable_internal_spoke = var.enable_internal_spoke

  # Merge tags with alias_tag for resource identification
  resource_tags = merge(
    var.tags,
    {
      SpokeAlias = var.alias_tag
    }
  )
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
# IAM Roles for ACK Controllers
#-------------------------------------------------------------------------------------------------------------------------------------------------#


# Spoke account ACK roles
resource "aws_iam_role" "spoke_ack" {
  provider = aws.spoke
  for_each = local.enable_external_spoke ? toset(var.ack_services) : []

  name = "${var.spoke_alias}-ack-${each.key}-spoke-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = var.ack_hub_roles[each.key].arn
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  description = "Spoke role for ${var.cluster_info.cluster_name} ${each.key}-ack-controller in Spoke: ${var.spoke_alias}"
  tags        = local.resource_tags
}




###################################################################################################################################################
# End of File
###################################################################################################################################################
