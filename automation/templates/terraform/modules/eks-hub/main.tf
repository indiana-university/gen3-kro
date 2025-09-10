
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = var.name
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = var.name
  }

  tags = var.tags
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# EKS Cluster Module
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.1"

  cluster_name                   = var.name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  cluster_compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  tags = {
    Blueprint  = var.name
    GithubRepo = "https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest"
  }
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# IAM Roles and Policies for ACK controllers
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Create IAM roles for ACK controllers
resource "aws_iam_role" "ack_controller" {
  for_each = toset(["iam", "ec2", "eks"])
  name        = "ack-${each.key}-controller-role-mgmt"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowEksAuthToAssumeRoleForPodIdentity"
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = ["sts:AssumeRole", "sts:TagSession"]
      }
    ]
  })
  description = "IRSA role for ACK ${each.key} controller deployment on EKS cluster using Helm charts"
  tags        = var.tags
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Then create IAM policies for ACK controllers if the policy is valid
resource "aws_iam_role_policy" "ack_controller_inline_policy" {
  for_each = toset(["iam", "ec2", "eks"])

  role   = aws_iam_role.ack_controller[each.key].name
  policy = can(jsondecode(data.http.inline_policy[each.key].body)) ? data.http.inline_policy[each.key].body : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "${each.key}:*"
        ]
        Resource = "*"
      }
    ]
  })
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Then attachment policy only when there's a valid policy ARN
resource "aws_iam_role_policy_attachment" "ack_controller_policy_attachment" {
  for_each = {
    for k, v in var.valid_policies : k => v
    if v != null && can(regex("^arn:aws", v))
  }

  role       = aws_iam_role.ack_controller[each.key].name
  policy_arn = each.value
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Cross-account access policy for ACK controllers
#-------------------------------------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role_policy" "ack_controller_cross_account_policy" {
  for_each = toset(["iam", "ec2", "eks"])

  role   = aws_iam_role.ack_controller[each.key].name
  policy = data.aws_iam_policy_document.ack_controller_cross_account_policy[each.key].json
}

