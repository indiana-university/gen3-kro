# Configuration Reference

This document describes the structure and options in `config/config.yaml` and related configuration files.

## config.yaml Structure

```yaml
hub:
  # Hub cluster identification and AWS settings
  alias: string                    # Short name for hub (e.g., "main-hub")
  aws_profile: string              # AWS CLI profile name
  aws_region: string               # AWS region (e.g., "us-east-1")
  cluster_name: string             # EKS cluster name
  kubernetes_version: string       # K8s version (e.g., "1.33")
  vpc_name: string                 # VPC name prefix
  
paths:
  # Storage and repository paths
  terraform_state_bucket: string   # S3 bucket for Terraform state
  terraform_state_key: string      # S3 key prefix (optional)
  terraform_state_region: string   # S3 bucket region (optional, defaults to hub region)
  argocd_repo_url: string          # Git repository URL for ArgoCD
  
addons:
  # Hub cluster add-ons (boolean flags)
  enable_metrics_server: bool      # Kubernetes metrics server
  enable_kyverno: bool             # Policy engine
  enable_argocd: bool              # GitOps controller
  enable_kro: bool                 # KRO controller
  enable_ack_iam: bool             # AWS ACK IAM controller
  enable_ack_eks: bool             # AWS ACK EKS controller
  enable_ack_ec2: bool             # AWS ACK EC2 controller
  enable_efs_csi: bool             # EFS CSI driver
  enable_cluster_autoscaler: bool  # Cluster autoscaler

networking:
  # Network configuration
  vpc_cidr: string                 # VPC CIDR block (e.g., "10.0.0.0/16")
  availability_zones: []string     # AZs to use (e.g., ["us-east-1a", "us-east-1b"])
  enable_nat_gateway: bool         # Enable NAT gateways
  single_nat_gateway: bool         # Use single NAT vs one per AZ
  enable_dns_hostnames: bool       # Enable DNS hostnames in VPC
  enable_dns_support: bool         # Enable DNS support in VPC

node_groups:
  # EKS managed node groups
  - name: string                   # Node group name
    instance_types: []string       # EC2 instance types
    desired_size: int              # Desired number of nodes
    min_size: int                  # Minimum nodes
    max_size: int                  # Maximum nodes
    disk_size: int                 # Root volume size (GB)
    labels: map[string]string      # Kubernetes node labels
    taints: []object               # Kubernetes node taints
      - key: string
        value: string
        effect: string             # NoSchedule|PreferNoSchedule|NoExecute

security:
  # Security settings
  enable_cluster_encryption: bool  # Enable EKS envelope encryption
  kms_key_id: string              # KMS key ARN (optional, auto-created if empty)
  enable_irsa: bool               # IAM Roles for Service Accounts
  enable_audit_logs: bool         # EKS control plane logging
  cluster_endpoint_private: bool  # Private API endpoint access
  cluster_endpoint_public: bool   # Public API endpoint access
  cluster_endpoint_public_cidrs: []string  # Allowed public CIDRs

tags:
  # Resource tags (applied to all resources)
  key: value
```

## Example: Production Hub

```yaml
hub:
  alias: "prod-hub"
  aws_profile: "production"
  aws_region: "us-east-1"
  cluster_name: "prod-hub-cluster"
  kubernetes_version: "1.33"
  vpc_name: "prod-hub-vpc"

paths:
  terraform_state_bucket: "myorg-terraform-state-prod"
  terraform_state_key: "hub/prod"
  argocd_repo_url: "https://github.com/myorg/infrastructure"

addons:
  enable_metrics_server: true
  enable_kyverno: true
  enable_argocd: true
  enable_kro: true
  enable_ack_iam: true
  enable_ack_eks: true
  enable_ack_ec2: false
  enable_efs_csi: true
  enable_cluster_autoscaler: true

networking:
  vpc_cidr: "10.0.0.0/16"
  availability_zones:
    - us-east-1a
    - us-east-1b
    - us-east-1c
  enable_nat_gateway: true
  single_nat_gateway: false
  enable_dns_hostnames: true
  enable_dns_support: true

node_groups:
  - name: system
    instance_types:
      - t3.large
    desired_size: 3
    min_size: 3
    max_size: 5
    disk_size: 100
    labels:
      role: system
    taints:
      - key: CriticalAddonsOnly
        value: "true"
        effect: NoSchedule
        
  - name: general
    instance_types:
      - t3.xlarge
    desired_size: 4
    min_size: 2
    max_size: 10
    disk_size: 100

security:
  enable_cluster_encryption: true
  enable_irsa: true
  enable_audit_logs: true
  cluster_endpoint_private: true
  cluster_endpoint_public: true
  cluster_endpoint_public_cidrs:
    - "203.0.113.0/24"  # Office IP range

tags:
  Environment: production
  ManagedBy: terraform
  Team: platform
  CostCenter: infrastructure
```

## Environment Overlays

### config/environments/staging.yaml

Environment-specific overrides applied on top of base config.yaml:

```yaml
environment: staging

# Overrides
cluster_name_suffix: staging
kubernetes_version: "1.33"

networking:
  vpc_cidr: "10.10.0.0/16"
  single_nat_gateway: true  # Cost savings

node_groups:
  - name: general
    instance_types:
      - t3.medium  # Smaller instances
    desired_size: 2
    min_size: 1
    max_size: 4

security:
  cluster_endpoint_public_cidrs:
    - "0.0.0.0/0"  # Open for development
```

### config/environments/prod.yaml

```yaml
environment: production

cluster_name_suffix: prod
kubernetes_version: "1.33"

networking:
  vpc_cidr: "10.0.0.0/16"
  single_nat_gateway: false  # HA

node_groups:
  - name: system
    instance_types:
      - t3.large
    desired_size: 3
    min_size: 3
    max_size: 5
    
  - name: general
    instance_types:
      - t3.xlarge
    desired_size: 4
    min_size: 2
    max_size: 10

security:
  cluster_endpoint_public_cidrs:
    - "203.0.113.0/24"  # Restricted
```

## Spoke Configuration

### config/spokes/template.yaml

Template for spoke cluster configurations:

```yaml
name: string                       # Spoke identifier
aws_account_id: string             # Target AWS account (12 digits)
aws_region: string                 # AWS region
environment: string                # staging|production|dev

cluster:
  name: string                     # EKS cluster name
  version: string                  # Kubernetes version
  endpoint_private_access: bool    # Private API access
  endpoint_public_access: bool     # Public API access

network:
  vpc_cidr: string                 # VPC CIDR block
  availability_zones: []string     # AZs to use
  enable_nat_gateway: bool
  single_nat_gateway: bool

node_groups:
  - name: string
    instance_types: []string
    desired_size: int
    min_size: int
    max_size: int
    disk_size: int
    labels: map[string]string
    taints: []object

addons:
  enable_cluster_autoscaler: bool
  enable_metrics_server: bool
  enable_efs_csi: bool

argocd:
  repo_url: string                 # Application git repository
  path: string                     # Path within repo
  target_revision: string          # Branch/tag
  sync_wave: string                # ArgoCD sync wave

iam_role_arn: string              # Cross-account IAM role (optional)

tags:
  key: value
```

### Example: Production Spoke

```yaml
name: data-platform-prod
aws_account_id: "123456789012"
aws_region: us-west-2
environment: production

cluster:
  name: data-platform-prod-cluster
  version: "1.33"
  endpoint_private_access: true
  endpoint_public_access: false

network:
  vpc_cidr: "10.100.0.0/16"
  availability_zones:
    - us-west-2a
    - us-west-2b
    - us-west-2c
  enable_nat_gateway: true
  single_nat_gateway: false

node_groups:
  - name: system
    instance_types:
      - t3.medium
    desired_size: 2
    min_size: 2
    max_size: 3
    disk_size: 50
    labels:
      role: system
      
  - name: data-processing
    instance_types:
      - r5.2xlarge
    desired_size: 4
    min_size: 2
    max_size: 20
    disk_size: 200
    labels:
      workload: data
    taints:
      - key: workload
        value: data
        effect: NoSchedule

addons:
  enable_cluster_autoscaler: true
  enable_metrics_server: true
  enable_efs_csi: true

argocd:
  repo_url: https://github.com/myorg/data-platform-apps
  path: manifests/production
  target_revision: main
  sync_wave: "3"

iam_role_arn: arn:aws:iam::123456789012:role/spoke-provisioner

tags:
  Team: data-engineering
  Environment: production
  CostCenter: analytics
```

## Configuration Validation

### Required Fields

**hub**:
- `alias` (string, no spaces)
- `aws_profile` (must exist in AWS CLI config)
- `aws_region` (valid AWS region)
- `cluster_name` (unique within account)
- `kubernetes_version` (supported EKS version)

**paths**:
- `terraform_state_bucket` (must exist or be creatable)

**networking**:
- `vpc_cidr` (valid CIDR, no conflicts)
- `availability_zones` (at least 2 for HA)

### Validation Command

```bash
# Validate configuration
./bootstrap/terragrunt-wrapper.sh staging validate

# Manual validation with yq
yq eval '.hub.aws_region' config/config.yaml
```

## Default Values

If not specified, the following defaults apply:

```yaml
networking:
  enable_nat_gateway: true
  single_nat_gateway: false
  enable_dns_hostnames: true
  enable_dns_support: true

security:
  enable_cluster_encryption: true
  enable_irsa: true
  enable_audit_logs: false
  cluster_endpoint_private: true
  cluster_endpoint_public: true
  cluster_endpoint_public_cidrs: ["0.0.0.0/0"]

node_groups:
  - disk_size: 50
    labels: {}
    taints: []
```

## Environment Variables

Configuration can reference environment variables:

```yaml
hub:
  aws_profile: ${AWS_PROFILE:-default}
  
paths:
  terraform_state_bucket: ${TF_STATE_BUCKET}
```

Set before running:
```bash
export TF_STATE_BUCKET=myorg-terraform-state
./bootstrap/terragrunt-wrapper.sh staging plan
```

## Configuration Hierarchy

Configurations are merged in order (last wins):

1. `config/config.yaml` (base)
2. `config/environments/${ENV}.yaml` (environment overlay)
3. Environment variables
4. Command-line flags (if applicable)

## Best Practices

### Naming

- **Clusters**: `<purpose>-<env>-<region>` (e.g., `hub-prod-us-east-1`)
- **VPCs**: Match cluster name
- **Node groups**: Descriptive (`system`, `general`, `gpu`, `spot`)

### CIDR Planning

- **Hub**: `10.0.0.0/16`
- **Spokes**: Non-overlapping ranges
  - Spoke 1: `10.1.0.0/16`
  - Spoke 2: `10.2.0.0/16`
  - etc.

### Security

- **Production**: 
  - `endpoint_public_access: false` or restricted CIDRs
  - `enable_cluster_encryption: true`
  - `enable_audit_logs: true`
  
- **Staging**: 
  - `endpoint_public_access: true` with CIDR restrictions
  - `enable_cluster_encryption: true`
  - `enable_audit_logs: false` (cost savings)

### High Availability

- Use 3+ availability zones
- Set `single_nat_gateway: false` for production
- Multiple node groups with different instance types

### Cost Optimization

- Staging: `single_nat_gateway: true`
- Use spot instances where appropriate
- Set reasonable `max_size` limits
- Disable unused addons

## Troubleshooting

### Invalid Configuration

**Error**: `Configuration validation failed`

**Solution**:
```bash
# Check YAML syntax
yq eval config/config.yaml

# Validate AWS profile
aws sts get-caller-identity --profile <profile-name>

# Check region
aws ec2 describe-regions --region <region>
```

### Overlapping CIDRs

**Error**: VPC CIDR conflicts with existing VPC

**Solution**: Use a different CIDR range for each spoke. Maintain a CIDR allocation document.

### Missing State Bucket

**Error**: S3 bucket does not exist

**Solution**:
```bash
# Create state bucket
aws s3 mb s3://myorg-terraform-state --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket myorg-terraform-state \
  --versioning-configuration Status=Enabled
```

## Reference

- [Terragrunt Configuration](https://terragrunt.gruntwork.io/docs/)
- [EKS Cluster Configuration](https://docs.aws.amazon.com/eks/latest/userguide/create-cluster.html)
- [VPC Design](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-cidr-blocks.html)
