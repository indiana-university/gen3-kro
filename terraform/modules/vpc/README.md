# VPC Module

This module creates a VPC for EKS cluster deployments with public and private subnets across multiple availability zones using **explicit subnet CIDR definitions**.

## Features

- Creates VPC with configurable CIDR block
- Configures public and private subnets with explicit CIDR blocks
- Supports multi-AZ deployments with precise subnet control
- Sets up NAT Gateway for private subnet internet access
- Tags subnets appropriately for EKS and Karpenter

## Key Changes from Previous Version

**Version 2.0** introduces explicit subnet configuration:

**Before (Calculated Subnets):**
- Used `excluded_azs`, `private_subnet_newbits`, `public_subnet_newbits`, `public_subnet_offset`
- Subnets calculated dynamically using `cidrsubnet()` function
- Less control over exact CIDR allocations

**After (Explicit Subnets):**
- Uses `availability_zones`, `private_subnet_cidrs`, `public_subnet_cidrs`
- Complete control over subnet CIDRs
- Easier to understand and document network layout
- Better for compliance and network planning

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| create | Whether to create VPC resources | bool | true | no |
| vpc_name | Name of the VPC | string | n/a | yes |
| vpc_cidr | CIDR block for the VPC | string | "10.0.0.0/16" | no |
| availability_zones | List of availability zones for subnets | list(string) | n/a | yes |
| private_subnet_cidrs | List of CIDR blocks for private subnets | list(string) | n/a | yes |
| public_subnet_cidrs | List of CIDR blocks for public subnets | list(string) | n/a | yes |
| cluster_name | Name of the EKS cluster (used for tagging subnets) | string | "" | no |
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

### Basic Example (3 Availability Zones)

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_name = "gen3-kro-hub"
  vpc_cidr = "10.0.0.0/16"

  availability_zones = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c"
  ]

  private_subnet_cidrs = [
    "10.0.0.0/20",   # 10.0.0.0 - 10.0.15.255 (4096 IPs)
    "10.0.16.0/20",  # 10.0.16.0 - 10.0.31.255
    "10.0.32.0/20"   # 10.0.32.0 - 10.0.47.255
  ]

  public_subnet_cidrs = [
    "10.0.240.0/24",  # 10.0.240.0 - 10.0.240.255 (256 IPs)
    "10.0.241.0/24",  # 10.0.241.0 - 10.0.241.255
    "10.0.242.0/24"   # 10.0.242.0 - 10.0.242.255
  ]

  cluster_name = "gen3-kro-hub"

  tags = {
    Terraform   = "true"
    Environment = "production"
    Cluster     = "gen3-kro-hub"
  }
}
```

### Multi-AZ High Availability (5 Availability Zones)

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_name = "gen3-kro-hub"
  vpc_cidr = "10.0.0.0/16"

  # Use all available AZs in us-east-1 (excluding 1e)
  availability_zones = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c",
    "us-east-1d",
    "us-east-1f"
  ]

  # Private subnets: /20 blocks (4096 IPs each)
  private_subnet_cidrs = [
    "10.0.0.0/20",    # us-east-1a
    "10.0.16.0/20",   # us-east-1b
    "10.0.32.0/20",   # us-east-1c
    "10.0.48.0/20",   # us-east-1d
    "10.0.64.0/20"    # us-east-1f
  ]

  # Public subnets: /24 blocks (256 IPs each)
  public_subnet_cidrs = [
    "10.0.240.0/24",  # us-east-1a
    "10.0.241.0/24",  # us-east-1b
    "10.0.242.0/24",  # us-east-1c
    "10.0.243.0/24",  # us-east-1d
    "10.0.244.0/24"   # us-east-1f
  ]

  cluster_name       = "gen3-kro-hub"
  enable_nat_gateway = true
  single_nat_gateway = true  # Cost optimization

  tags = {
    Terraform   = "true"
    Environment = "production"
    Cluster     = "gen3-kro-hub"
  }
}
```

### Production with Multiple NAT Gateways

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_name = "gen3-kro-production"
  vpc_cidr = "10.0.0.0/16"

  availability_zones = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c"
  ]

  private_subnet_cidrs = [
    "10.0.0.0/20",
    "10.0.16.0/20",
    "10.0.32.0/20"
  ]

  public_subnet_cidrs = [
    "10.0.240.0/24",
    "10.0.241.0/24",
    "10.0.242.0/24"
  ]

  cluster_name       = "gen3-kro-production"
  enable_nat_gateway = true
  single_nat_gateway = false  # NAT Gateway per AZ for HA

  # Custom subnet tags
  private_subnet_tags = {
    Tier = "private"
  }

  public_subnet_tags = {
    Tier = "public"
  }

  tags = {
    Terraform   = "true"
    Environment = "production"
    Cluster     = "gen3-kro-production"
    CostCenter  = "platform-engineering"
  }
}
```

## Subnet Sizing Guidelines

### Private Subnets (EKS Nodes)

Recommended sizes based on cluster scale:

| Cluster Size | Subnet Size | CIDR | IPs Available | Use Case |
|--------------|-------------|------|---------------|----------|
| Small | /24 | 256 IPs | ~250 | Dev/test clusters |
| Medium | /20 | 4,096 IPs | ~4,000 | Production, <100 nodes |
| Large | /19 | 8,192 IPs | ~8,000 | Production, <200 nodes |
| X-Large | /18 | 16,384 IPs | ~16,000 | Large-scale production |

**Note:** AWS reserves 5 IPs per subnet (.0, .1, .2, .3, .255)

### Public Subnets (Load Balancers)

Recommended: **/24** (256 IPs) per AZ
- Used for: ALB/NLB, NAT Gateways, bastion hosts
- 256 IPs per AZ is sufficient for most deployments

### VPC CIDR Selection

| VPC CIDR | Total IPs | Recommended Use |
|----------|-----------|-----------------|
| /16 | 65,536 | Standard (recommended) |
| /17 | 32,768 | Medium environments |
| /18 | 16,384 | Smaller environments |

## Subnet Layout Examples

### Example 1: 10.0.0.0/16 with 5 AZs

```
VPC: 10.0.0.0/16 (65,536 IPs)

Private Subnets (4,096 IPs each):
├── us-east-1a: 10.0.0.0/20   (10.0.0.0   - 10.0.15.255)
├── us-east-1b: 10.0.16.0/20  (10.0.16.0  - 10.0.31.255)
├── us-east-1c: 10.0.32.0/20  (10.0.32.0  - 10.0.47.255)
├── us-east-1d: 10.0.48.0/20  (10.0.48.0  - 10.0.63.255)
└── us-east-1f: 10.0.64.0/20  (10.0.64.0  - 10.0.79.255)

Public Subnets (256 IPs each):
├── us-east-1a: 10.0.240.0/24 (10.0.240.0 - 10.0.240.255)
├── us-east-1b: 10.0.241.0/24 (10.0.241.0 - 10.0.241.255)
├── us-east-1c: 10.0.242.0/24 (10.0.242.0 - 10.0.242.255)
├── us-east-1d: 10.0.243.0/24 (10.0.243.0 - 10.0.243.255)
└── us-east-1f: 10.0.244.0/24 (10.0.244.0 - 10.0.244.255)

Reserved Space: 10.0.80.0 - 10.0.239.255 (future expansion)
```

### Example 2: 10.1.0.0/16 (Spoke Cluster)

```
VPC: 10.1.0.0/16

Private Subnets:
├── us-west-2a: 10.1.0.0/20
├── us-west-2b: 10.1.16.0/20
└── us-west-2c: 10.1.32.0/20

Public Subnets:
├── us-west-2a: 10.1.240.0/24
├── us-west-2b: 10.1.241.0/24
└── us-west-2c: 10.1.242.0/24
```

## Migration from Calculated Subnets

### Old Configuration (Deprecated)

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_name = "gen3-kro-hub"
  vpc_cidr = "10.0.0.0/16"

  excluded_azs            = ["us-east-1e"]
  private_subnet_newbits  = 4    # Creates /20 subnets
  public_subnet_newbits   = 8    # Creates /24 subnets
  public_subnet_offset    = 240  # Starts at 10.0.240.0
}
```

### New Configuration (Current)

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_name = "gen3-kro-hub"
  vpc_cidr = "10.0.0.0/16"

  availability_zones = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c",
    "us-east-1d",
    "us-east-1f"
  ]

  private_subnet_cidrs = [
    "10.0.0.0/20",
    "10.0.16.0/20",
    "10.0.32.0/20",
    "10.0.48.0/20",
    "10.0.64.0/20"
  ]

  public_subnet_cidrs = [
    "10.0.240.0/24",
    "10.0.241.0/24",
    "10.0.242.0/24",
    "10.0.243.0/24",
    "10.0.244.0/24"
  ]
}
```

## Validation

### CIDR Consistency Check

Ensure subnet counts match:

```bash
# Lengths must be equal
length(availability_zones) == length(private_subnet_cidrs)
length(availability_zones) == length(public_subnet_cidrs)
```

### Subnet Overlap Check

Verify no overlapping CIDRs:

```bash
# Use online CIDR calculator or:
terraform console
> cidrsubnet("10.0.0.0/20", 0, 0)
"10.0.0.0/20"
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |
| terraform-aws-modules/vpc/aws | 6.4.0 |

## License

Apache-2.0 License

