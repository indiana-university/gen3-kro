# Spoke IAM Terraform Composition

This Terraform composition provisions IAM roles and policies for spoke clusters in a hub-spoke architecture. It handles cross-account IAM setup for ACK controllers and addons that need to manage AWS resources in spoke accounts.

## Overview

The spoke composition handles IAM-only provisioning for spoke accounts. It creates:

- **IAM Policies**: Loaded from `iam/gen3/<spoke_alias>/` directory
- **Spoke Roles**: IAM roles with trust relationships to hub pod identities
- **ArgoCD ConfigMap**: Spoke configuration for ArgoCD generators
- **Cross-Account Trust**: Allows hub ACK controllers to assume spoke roles

**Note**: The spoke composition does **NOT** create:
- VPCs (managed by KRO from hub)
- EKS clusters (managed by KRO from hub)
- Kubernetes resources (managed by ArgoCD from hub)

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    SPOKE COMPOSITION                       │
│                    (IAM Only)                              │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           IAM Policy Module                          │  │
│  │  (Loads policies from iam/gen3/<spoke_alias>/)       │  │
│  │                                                      │  │
│  │  • acks/<service>/internal-policy.json               │  │
│  │  • addons/<service>/internal-policy.json             │  │
│  │  • override-policy-*.json                            │  │
│  │  • managed-policy-arns.txt                           │  │
│  └──────────────────────────────────────────────────────┘  │
│                         │                                  │
│                         ▼                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           Spoke Role Module                          │  │
│  │  (Creates IAM roles for ACK/addons)                  │  │
│  │                                                      │  │
│  │  Role Name: <cluster_name>-<service>                 │  │
│  │  Trust: Hub pod identity role ARN                    │  │
│  │  Policy: From IAM policy module                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                         │                                  │
│                         ▼                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           ArgoCD ConfigMap Module                    │  │
│  │  (Creates ConfigMap with spoke role info)            │  │
│  │                                                      │  │
│  │  • Role ARNs                                         │  │
│  │  • Service configurations                            │  │
│  │  • Cluster metadata                                  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
└────────────────────────────────────────────────────────────┘
                         │
                         │ Trust Relationship
                         ▼
┌────────────────────────────────────────────────────────────┐
│                    HUB CLUSTER                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │    Hub Pod Identity (ACK Controller)                 │  │
│  │    Role ARN: arn:aws:iam::HUB_ACCT:role/hub-ec2      │  │
│  │                                                      │  │
│  │    AssumeRole Policy:                                │  │
│  │    → arn:aws:iam::SPOKE_ACCT:role/spoke1-ec2         │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

## IAM Policy Scenarios

The spoke composition is specifically designed for **cross-account** IAM scenarios. It handles two use cases:

### 1. Cross-Account with Role Creation (Different AWS Account)

**When**: Spoke account ≠ Hub account AND no pre-existing roles
**What happens**:
- Spoke composition: Creates IAM role with trust policy to hub role
- Spoke composition: Attaches policies loaded from `iam/gen3/<spoke_alias>/`
- Hub composition: Creates cross-account policy allowing AssumeRole to spoke role
- ACK Controller: Runs in hub, assumes spoke role to manage spoke resources

```
Hub Account (111111111111)              Spoke Account (222222222222)
┌─────────────────────┐                ┌──────────────────────┐
│ ACK EC2 Controller  │                │  Spoke EC2 Role      │
│ Role: hub-ack-ec2   │───AssumeRole──→│  Role: spoke1-ec2    │
│                     │                │  Policy: EC2 actions │
└─────────────────────┘                └──────────────────────┘
```

### 2. Cross-Account with Override ARNs (Pre-existing Roles)

**When**: Spoke account has externally managed roles
**What happens**:
- Spoke composition: Skips role creation
- Spoke composition: Creates ConfigMap with provided ARNs
- Hub composition: Creates cross-account policy to provided ARNs
- Uses externally managed roles and policies

```
Hub Account (111111111111)         External Spoke Account (222222222222)
┌─────────────────────┐              ┌──────────────────────┐
│ ACK EC2 Controller  │              │  Pre-existing Role   │
│ Role: hub-ack-ec2   │──AssumeRole─→│  Role: custom-ec2    │
│                     │              │  (Managed externally)│
└─────────────────────┘              └──────────────────────┘
         │
         │ ARN Reference
         ↓
  ┌──────────────┐
  │  ConfigMap   │
  │  (in hub)    │
  └──────────────┘
```

### Hub-Internal Scenario (NOT Handled by Spoke Composition)

**When**: Spoke "account" = Hub account (same AWS account)
**What happens**:
- **Spoke composition is NOT used**
- Hub pod identities use internal policies directly
- No cross-account role assumption needed
- Simpler setup managed entirely by hub composition

```
Hub Account (111111111111)
┌─────────────────────┐
│ ACK EC2 Controller  │
│ Role: hub-ack-ec2   │
│ Policy: EC2 actions │
│ (internal policy)   │
└─────────────────────┘
```

**Important**: The spoke Terraform composition is **only** for cross-account scenarios. For hub-internal (same account) scenarios, the hub composition handles everything and the spoke composition should not be deployed.

## Module Flow

### 1. Determine Services Needing Roles

```hcl
locals {
  # Services that need role creation (not using override ARN)
  services_needing_roles = {
    for k, v in merge(
      {
        for svc_name, svc_config in var.ack_configs :
        svc_name => {
          service_type = "acks"
          hub_role_arn = lookup(svc_config, "hub_role_arn", "")
        }
        if lookup(svc_config, "override_arn", "") == ""
      },
      {
        for addon_name, addon_config in var.addon_configs :
        addon_name => {
          service_type = "addons"
          hub_role_arn = lookup(addon_config, "hub_role_arn", "")
        }
        if lookup(addon_config, "enable_pod_identity", false) &&
           lookup(addon_config, "override_arn", "") == ""
      }
    ) : k => v
  }

  # Services using override ARN (skip role creation)
  services_using_override = {
    for k, v in merge(
      {
        for svc_name, svc_config in var.ack_configs :
        svc_name => {
          service_type = "acks"
          override_arn = lookup(svc_config, "override_arn", "")
        }
        if lookup(svc_config, "override_arn", "") != ""
      },
      {
        for addon_name, addon_config in var.addon_configs :
        addon_name => {
          service_type = "addons"
          override_arn = lookup(addon_config, "override_arn", "")
        }
        if lookup(addon_config, "enable_pod_identity", false) &&
           lookup(addon_config, "override_arn", "") != ""
      }
    ) : k => v
  }
}
```

### 2. Load IAM Policies

```hcl
module "service_policy" {
  source = "../../modules/iam-policy"

  for_each = local.services_needing_roles

  service_type         = each.value.service_type
  service_name         = each.key
  context              = "spoke-${var.spoke_alias}"
  iam_policy_base_path = var.iam_base_path
  repo_root_path       = "${path.root}/../../../.."
}
```

**Loads from**: `iam/gen3/<spoke_alias>/<service_type>/<service_name>/`

### 3. Create Spoke Roles

```hcl
module "service_role" {
  source = "../../modules/spoke-role"

  for_each = local.services_needing_roles

  service_type              = each.value.service_type
  cluster_name              = var.cluster_name
  service_name              = each.key
  spoke_alias               = var.spoke_alias
  hub_pod_identity_role_arn = each.value.hub_role_arn

  # Get loaded policy from iam-policy module
  combined_policy_json = try(module.service_policy[each.key].inline_policy_document, null)
  policy_arns          = try(module.service_policy[each.key].managed_policy_arns, {})
  has_inline_policy    = try(module.service_policy[each.key].has_inline_policy, false)
}
```

**Creates**: IAM role with trust policy to hub pod identity

### 4. Create ArgoCD ConfigMap (in Hub Cluster)

**Important**: The ConfigMap is created in the **hub cluster's ArgoCD namespace**, not in the spoke account. This allows ArgoCD ApplicationSets in the hub to query spoke role information.

```hcl
module "argocd_configmap" {
  source = "../../modules/spokes-configmap"

  cluster_name     = var.cluster_name
  argocd_namespace = var.argocd_namespace

  pod_identities = merge(
    # Roles created by this spoke
    {
      for k, v in module.service_role : k => {
        role_arn      = v.role_arn
        role_name     = v.role_name
        service_type  = lookup(local.services_needing_roles[k], "service_type", "unknown")
        service_name  = k
        policy_source = "spoke_created"
      }
    },
    # Roles using override ARNs
    {
      for k, v in local.services_using_override : k => {
        role_arn      = lookup(v, "override_arn", "")
        role_name     = split("/", lookup(v, "override_arn", "unknown"))[length(split("/", lookup(v, "override_arn", "unknown"))) - 1]
        service_type  = lookup(v, "service_type", "unknown")
        service_name  = k
        policy_source = "spoke_override"
      }
    }
  )

  ack_configs   = var.ack_configs
  addon_configs = var.addon_configs
}
```

**ConfigMap Location**: The `spokes-configmap` module uses the `kubernetes` provider configured for the **hub cluster**, so the ConfigMap is created in the hub's ArgoCD namespace, not in the spoke account.

## Input Variables

### Core Configuration

| Variable       | Type     | Description                       | Required |
|----------------|----------|-----------------------------------|----------|
| `spoke_alias`  | `string` | Spoke identifier (e.g., "spoke1") | Yes      |
| `cluster_name` | `string` | Expected cluster name             | Yes      |
| `region`       | `string` | AWS region                        | Yes      |

### ACK Configuration

| Variable      | Type          | Description                   | Default |
|---------------|---------------|-------------------------------|---------|
| `ack_configs` | `map(object)` | ACK controller configurations | `{}`    |

Each ACK config object:
```hcl
{
  hub_role_arn = string      # Hub pod identity role ARN (for trust policy)
  override_arn = string      # Optional: Use existing role instead of creating
  namespace    = string      # Kubernetes namespace
  service_account = string   # Kubernetes service account
}
```

Example:
```hcl
ack_configs = {
  ec2 = {
    hub_role_arn    = "arn:aws:iam::111111111111:role/hub-ack-ec2"
    override_arn    = ""  # Empty = create role
    namespace       = "ack-system"
    service_account = "ack-ec2-sa"
  }
  eks = {
    hub_role_arn    = "arn:aws:iam::111111111111:role/hub-ack-eks"
    override_arn    = "arn:aws:iam::222222222222:role/pre-existing-eks-role"  # Use existing
    namespace       = "ack-system"
    service_account = "ack-eks-sa"
  }
}
```

### Addon Configuration

| Variable        | Type          | Description                   | Default |
|-----------------|---------------|-------------------------------|---------|
| `addon_configs` | `map(object)` | Platform addon configurations | `{}`    |

Same structure as `ack_configs`

### IAM Configuration

| Variable           | Type     | Description                 | Default       |
|--------------------|----------|-----------------------------|---------------|
| `iam_base_path`    | `string` | Base path in iam/ directory | `"gen3"`      |
| `iam_repo_root`    | `string` | Repository root path        | Auto-detected |
| `iam_git_repo_url` | `string` | Git repo URL (for metadata) | `""`          |
| `iam_git_branch`   | `string` | Git branch (for metadata)   | `"main"`      |

### ArgoCD Configuration

| Variable           | Type     | Description      | Default    |
|--------------------|----------|------------------|------------|
| `argocd_namespace` | `string` | ArgoCD namespace | `"argocd"` |

### Cluster Information (Optional)

| Variable       | Type          | Description               | Default |
|----------------|---------------|---------------------------|---------|
| `cluster_info` | `map(string)` | Cluster metadata from hub | `{}`    |

Example:
```hcl
cluster_info = {
  cluster_endpoint = "https://xxx.eks.amazonaws.com"
  vpc_id           = "vpc-xxxxxxxxx"
  region           = "us-east-1"
}
```

## Outputs

| Output             | Description                      |
|--------------------|----------------------------------|
| `spoke_role_arns`  | Map of service name to role ARN  |
| `spoke_role_names` | Map of service name to role name |
| `configmap_name`   | ArgoCD ConfigMap name            |

## Usage Example

### Terragrunt Configuration

```hcl
# live/aws/us-east-1/spoke1-iam/terragrunt.hcl

terraform {
  source = "../../../../terraform/combinations/spoke"
}

include "root" {
  path = find_in_parent_folders()
}

# Get hub outputs for role ARNs
dependency "hub" {
  config_path = "../gen3-kro-hub"

  mock_outputs = {
    ack_role_arns = {
      ec2 = "arn:aws:iam::111111111111:role/hub-ack-ec2"
      eks = "arn:aws:iam::111111111111:role/hub-ack-eks"
      iam = "arn:aws:iam::111111111111:role/hub-ack-iam"
    }
  }
}

inputs = {
  # Core
  spoke_alias  = "spoke1"
  cluster_name = "spoke1-cluster"
  region       = "us-east-1"

  # ACK Controllers
  ack_configs = {
    ec2 = {
      hub_role_arn    = dependency.hub.outputs.ack_role_arns["ec2"]
      override_arn    = ""  # Create role
      namespace       = "ack-system"
      service_account = "ack-ec2-sa"
    }
    eks = {
      hub_role_arn    = dependency.hub.outputs.ack_role_arns["eks"]
      override_arn    = ""  # Create role
      namespace       = "ack-system"
      service_account = "ack-eks-sa"
    }
    iam = {
      hub_role_arn    = dependency.hub.outputs.ack_role_arns["iam"]
      override_arn    = ""  # Create role
      namespace       = "ack-system"
      service_account = "ack-iam-sa"
    }
  }

  # IAM
  iam_base_path    = "gen3"
  iam_git_repo_url = "https://github.com/indiana-university/gen3-kro.git"
  iam_git_branch   = "main"

  # ArgoCD
  argocd_namespace = "argocd"

  # Tags
  tags = {
    Environment = "production"
    ManagedBy   = "Terragrunt"
    Project     = "Gen3-KRO"
    Spoke       = "spoke1"
  }
}
```

### With Override ARNs (Pre-existing Roles)

```hcl
inputs = {
  spoke_alias  = "spoke2"
  cluster_name = "spoke2-cluster"

  ack_configs = {
    ec2 = {
      hub_role_arn = dependency.hub.outputs.ack_role_arns["ec2"]
      override_arn = "arn:aws:iam::333333333333:role/legacy-ec2-role"  # Use existing
    }
    s3 = {
      hub_role_arn = dependency.hub.outputs.ack_role_arns["s3"]
      override_arn = "arn:aws:iam::333333333333:role/legacy-s3-role"  # Use existing
    }
  }
}
```

## Deployment Process

### 1. Deploy Hub First

```bash
cd live/aws/us-east-1/gen3-kro-hub
terragrunt apply
```

**Capture hub role ARNs** from outputs

### 2. Create IAM Policies

Create policy files in `iam/gen3/<spoke_alias>/`:

```bash
mkdir -p iam/gen3/spoke1/acks/ec2
cat > iam/gen3/spoke1/acks/ec2/internal-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:CreateTags",
        "ec2:DeleteTags"
      ],
      "Resource": "*"
    }
  ]
}
EOF
```

### 3. Initialize Spoke IAM

```bash
cd live/aws/us-east-1/spoke1-iam
terragrunt init
```

### 4. Plan

```bash
terragrunt plan
```

Review:
- Spoke roles will be created with correct trust policies
- Policies loaded from correct paths
- ConfigMap will be created with role ARNs

### 5. Apply

```bash
terragrunt apply
```

Deployment takes ~1-2 minutes (IAM only, no cluster resources)

### 6. Verify

```bash
# List created roles
aws iam list-roles --query 'Roles[?starts_with(RoleName, `spoke1-`)]'

# Describe trust policy
aws iam get-role --role-name spoke1-ec2 --query 'Role.AssumeRolePolicyDocument'

# Verify inline policy
aws iam get-role-policy --role-name spoke1-ec2 --policy-name spoke1-ec2-inline-policy
```

### 7. Update Hub with Spoke ARNs

After spoke IAM is created, update hub with spoke role ARNs:

```hcl
# live/aws/us-east-1/gen3-kro-hub/terragrunt.hcl

dependency "spoke1_iam" {
  config_path = "../spoke1-iam"
}

inputs = {
  # ... existing config ...

  enable_multi_acct = true
  spoke_arn_inputs = {
    spoke1 = {
      for svc, arn in dependency.spoke1_iam.outputs.spoke_role_arns :
      svc => { role_arn = arn }
    }
  }
}
```

Apply hub to attach cross-account policies:

```bash
cd live/aws/us-east-1/gen3-kro-hub
terragrunt apply
```

## IAM Policy Structure

### Directory Layout

```
iam/gen3/<spoke_alias>/
├── acks/
│   ├── ec2/
│   │   ├── internal-policy.json          # Main policy
│   │   ├── override-policy-custom.json   # Additional policy
│   │   └── managed-policy-arns.txt       # AWS managed policies
│   ├── eks/
│   │   └── internal-policy.json
│   └── iam/
│       └── internal-policy.json
└── addons/
    └── external-secrets/
        └── internal-policy.json
```

### Policy Files

**internal-policy.json**: Main inline policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ec2:Describe*"],
      "Resource": "*"
    }
  ]
}
```

**override-policy-*.json**: Additional inline policies (merged)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ec2:CreateTags"],
      "Resource": "*"
    }
  ]
}
```

**managed-policy-arns.txt**: AWS managed policy ARNs (one per line)
```
arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
```

## Cross-Account Trust Policy

The spoke role trusts the hub pod identity:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/hub-ack-ec2"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Hub pod identity can then assume this role:

```bash
# From hub ACK controller pod
aws sts assume-role \
  --role-arn arn:aws:iam::222222222222:role/spoke1-ec2 \
  --role-session-name spoke1-session
```

## ArgoCD ConfigMap

The ConfigMap is created in the **hub cluster's ArgoCD namespace**, not in the spoke account. This is managed by the `spokes-configmap` module which uses the kubernetes provider configured for the hub cluster.

**ConfigMap Structure**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: spoke1-cluster-argocd-settings
  namespace: argocd  # In HUB cluster
data:
  ack.yaml: |
    ec2:
      enabled: true
      namespace: ack-system
      serviceAccount: ack-ec2-controller
      hubRoleArn: arn:aws:iam::222222222222:role/spoke1-ec2
      policyArn: ""
      spokes: {}
    eks:
      enabled: true
      namespace: ack-system
      serviceAccount: ack-eks-controller
      hubRoleArn: arn:aws:iam::222222222222:role/spoke1-eks
      policyArn: ""
      spokes: {}
  addons.yaml: |
    {}  # Or addon configurations if applicable
  cluster-info.yaml: |
    name: spoke1-cluster
    region: us-east-1
    accountId: "222222222222"
  gitops-context.yaml: |
    spoke_alias: spoke1
    spoke_region: us-east-1
```

**Key Points**:
- ConfigMap resides in **hub cluster**, not spoke account
- ArgoCD ApplicationSets in the hub can query this ConfigMap
- The `spokes-configmap` module requires kubernetes provider access to hub cluster
- Spoke composition must have network connectivity to hub EKS API server

## Maintenance

### Add New ACK Controller

1. **Create IAM policy**:
```bash
mkdir -p iam/gen3/spoke1/acks/s3
cat > iam/gen3/spoke1/acks/s3/internal-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": "*"
    }
  ]
}
EOF
```

2. **Update terragrunt.hcl**:
```hcl
ack_configs = {
  # ... existing ...
  s3 = {
    hub_role_arn    = dependency.hub.outputs.ack_role_arns["s3"]
    override_arn    = ""
    namespace       = "ack-system"
    service_account = "ack-s3-sa"
  }
}
```

3. **Apply**:
```bash
terragrunt apply
```

### Update IAM Policy

1. **Modify policy file**: Edit `iam/gen3/spoke1/acks/ec2/internal-policy.json`
2. **Apply**: `terragrunt apply`
3. **No role recreation**: Policy is updated in-place

### Destroy

```bash
# Remove spoke IAM roles
cd live/aws/us-east-1/spoke1-iam
terragrunt destroy

# Update hub to remove spoke from spoke_arn_inputs
cd live/aws/us-east-1/gen3-kro-hub
# Edit terragrunt.hcl to remove spoke1 from spoke_arn_inputs
terragrunt apply
```

## Troubleshooting

### Trust policy error

**Symptom**: Hub ACK controller cannot assume spoke role

**Check**:
```bash
# Verify trust policy in spoke role
aws iam get-role --role-name spoke1-ec2 --query 'Role.AssumeRolePolicyDocument' --profile <spoke-profile>

# Expected output should show hub pod identity role ARN as trusted principal
```

**Solution**:
- Verify `hub_role_arn` in spoke's `ack_configs` matches actual hub pod identity role ARN
- Get correct hub role ARN from hub outputs: `terragrunt output ack_pod_identities`
- Ensure hub role ARN is passed correctly via dependency block in spoke's terragrunt.hcl

### Policy not loading

**Symptom**: Spoke role created without policy

**Check**:
```bash
# Verify policy file exists
ls iam/gen3/spoke1/acks/ec2/internal-policy.json

# Check Terraform plan for policy loading
terragrunt plan 2>&1 | grep -A 5 "iam_policy"

# Verify inline policy attached to role
aws iam get-role-policy --role-name spoke1-ec2 --policy-name spoke1-ec2-inline-policy --profile <spoke-profile>
```

**Solution**:
- Ensure policy path matches: `iam/gen3/<spoke_alias>/<service_type>/<service>/internal-policy.json`
- For ACK controllers: `iam/gen3/spoke1/acks/ec2/internal-policy.json`
- For addons: `iam/gen3/spoke1/addons/<addon-name>/internal-policy.json`
- Verify `iam_base_path = "gen3"` in spoke's terragrunt inputs
- Check `spoke_alias` variable matches directory name

### ConfigMap not created in hub cluster

**Symptom**: ArgoCD cannot find spoke configuration

**Check**:
```bash
# ConfigMap is in HUB cluster, not spoke account
kubectl get configmap spoke1-cluster-argocd-settings -n argocd --context <hub-cluster-context>
```

**Solution**:
- Ensure spoke composition has kubernetes provider configured for hub cluster
- Verify network connectivity from spoke Terraform execution to hub EKS API server
- Check `argocd_namespace` variable is correct (default: "argocd")
- Verify AWS credentials have access to hub cluster

## See Also

- [Hub Composition](../hub/README.md)
- [Terraform Modules](../../modules/README.md)
- [IAM Policy Module](../../modules/iam-policy/README.md)
- [Spoke Role Module](../../modules/spoke-role/README.md)
- [Terragrunt Deployment Guide](../../../docs/setup-terragrunt.md)
