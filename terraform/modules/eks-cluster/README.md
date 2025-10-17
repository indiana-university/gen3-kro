# EKS Cluster Module

This module creates an Amazon EKS cluster with configurable compute settings.

## Features

- Creates EKS cluster with specified Kubernetes version
- Configures cluster endpoint access
- Sets up cluster compute configuration
- Provides cluster authentication token
- Lifecycle protection for cluster renames

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the EKS cluster | string | n/a | yes |
| cluster_version | Kubernetes version for the EKS cluster | string | "1.31" | no |
| vpc_id | VPC ID where the cluster will be deployed | string | n/a | yes |
| subnet_ids | List of subnet IDs for the EKS cluster | list(string) | n/a | yes |
| cluster_endpoint_public_access | Enable public API server endpoint | bool | true | no |
| enable_cluster_creator_admin_permissions | Enable cluster creator admin permissions | bool | true | no |
| cluster_compute_config | Cluster compute configuration | any | see below | no |
| tags | Tags to apply to all cluster resources | map(string) | {} | no |

Default `cluster_compute_config`:
```hcl
{
  enabled    = true
  node_pools = ["general-purpose", "system"]
}
```

## Outputs

| Name | Description |
|------|-------------|
| cluster_name | The name of the EKS cluster |
| cluster_id | The ID of the EKS cluster |
| cluster_arn | The ARN of the EKS cluster |
| cluster_endpoint | Endpoint for the EKS cluster API server |
| cluster_version | The Kubernetes version of the cluster |
| cluster_platform_version | The platform version of the EKS cluster |
| cluster_security_group_id | Security group ID attached to the EKS cluster |
| cluster_certificate_authority_data | Base64 encoded certificate data (sensitive) |
| oidc_provider | The OpenID Connect identity provider |
| oidc_provider_arn | ARN of the OIDC Provider for the EKS cluster |
| cluster_auth_token | Authentication token for the EKS cluster (sensitive) |
| account_id | AWS Account ID |
| cluster_info | Consolidated cluster information object |

## Usage

```hcl
module "eks_cluster" {
  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/eks-cluster?ref=main"

  cluster_name    = "my-cluster"
  cluster_version = "1.31"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  tags = {
    Environment = "production"
    Project     = "gen3-kro"
  }
}
```

## Dependencies

This module depends on:
- VPC module (requires vpc_id and subnet_ids)
