# VPC Module

This module creates a VPC for EKS cluster deployments with public and private subnets across multiple availability zones.

## Features

- Creates VPC with configurable CIDR block
- Configures public and private subnets across availability zones
- Sets up NAT Gateway for private subnet internet access
- Tags subnets appropriately for EKS and Karpenter

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| vpc_name | Name of the VPC | string | n/a | yes |
| vpc_cidr | CIDR block for the VPC | string | "10.0.0.0/16" | no |
| azs | List of availability zones | list(string) | [] | no |
| cluster_name | Name of the EKS cluster (used for tagging subnets) | string | n/a | yes |
| enable_nat_gateway | Enable NAT Gateway for private subnets | bool | true | no |
| single_nat_gateway | Use a single NAT Gateway for all private subnets | bool | true | no |
| public_subnet_tags | Additional tags for public subnets | map(string) | {} | no |
| private_subnet_tags | Additional tags for private subnets | map(string) | {} | no |
| tags | Tags to apply to all VPC resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | The ID of the VPC |
| vpc_cidr | The CIDR block of the VPC |
| private_subnets | List of IDs of private subnets |
| public_subnets | List of IDs of public subnets |
| private_subnet_cidrs | List of CIDR blocks of private subnets |
| public_subnet_cidrs | List of CIDR blocks of public subnets |
| nat_gateway_ids | List of NAT Gateway IDs |
| azs | List of availability zones used |
| vpc_arn | The ARN of the VPC |

## Usage

```hcl
module "vpc" {
  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/vpc?ref=main"

  vpc_name     = "my-vpc"
  vpc_cidr     = "10.0.0.0/16"
  cluster_name = "my-cluster"

  tags = {
    Environment = "production"
    Project     = "gen3-kro"
  }
}
```
