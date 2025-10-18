# Generic Pod Identity Module

Universal Terraform module for creating EKS Pod Identities with IAM roles and policies. Supports ACK controllers, Kubernetes addons, ArgoCD, and custom services.

## Overview

This module is a wrapper around `terraform-aws-modules/eks-pod-identity/aws` with integrated policy loading capabilities. It automatically loads IAM policies from your filesystem or Git repository based on service type and name, or accepts custom policies directly.

**Key Features:**
- **Universal Support**: Works with ACK, addons, ArgoCD, and custom services
- **Automatic Policy Loading**: Integrates with the `iam-policy` module to load policies from filesystem
- **Context-Aware**: Supports hub and spoke contexts for multi-cluster setups
- **Flexible Policy Sources**: Load from filesystem, Git, or provide custom policies
- **Cross-Account Support**: Merge cross-account policies with inline policies
- **Consistent Naming**: Role names follow pattern `{cluster}-{type}-{service}`

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Generic Pod Identity Module                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ 1. Service Identification                                       │ │
│  │    - service_type: ack | addon | argocd | custom               │ │
│  │    - service_name: e.g., "iam", "aws-load-balancer-controller" │ │
│  │    - context: hub | spoke1 | spoke2                            │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                             ↓                                         │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ 2. IAM Policy Loading (via iam-policy module)                  │ │
│  │    Path: iam/{service_type}/{context}/{service_name}/          │ │
│  │    - recommended_inline_policy.json (primary)                  │ │
│  │    - override.json (optional context override)                 │ │
│  │    - managed_arns.txt (managed policies)                       │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                             ↓                                         │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ 3. Policy Merging                                               │ │
│  │    - Source: inline policies from filesystem                   │ │
│  │    - Override: context-specific overrides                      │ │
│  │    - Cross-account: additional cross-account policies          │ │
│  │    - Managed: AWS managed policy ARNs                          │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                             ↓                                         │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ 4. Pod Identity Creation (terraform-aws-modules/eks-pod-id)    │ │
│  │    - IAM Role: {cluster}-{service_type}-{service_name}         │ │
│  │    - Trust Policy: EKS Pod Identity service principal          │ │
│  │    - Inline Policies: Attached as custom policy                │ │
│  │    - Managed ARNs: Attached as additional policies             │ │
│  │    - Association: {namespace}/{service_account} → cluster      │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

## Usage Examples

### ACK Controller (IAM Service)

```hcl
module "ack_iam" {
  source = "./modules/pod-identity"

  service_type = "ack"
  service_name = "iam"
  context      = "hub"

  cluster_name    = "gen3-kro-hub"
  namespace       = "ack-system"
  service_account = "ack-iam-controller"

  repo_root_path = "/workspaces/gen3-kro"

  tags = {
    Terraform   = "true"
    Environment = "production"
    Cluster     = "gen3-kro-hub"
  }
}

# Output: Role ARN = arn:aws:iam::123456789012:role/gen3-kro-hub-ack-iam
```

### Kubernetes Addon (AWS Load Balancer Controller)

```hcl
module "addon_alb" {
  source = "./modules/pod-identity"

  service_type = "addon"
  service_name = "aws-load-balancer-controller"
  context      = "hub"

  cluster_name    = "gen3-kro-hub"
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"

  repo_root_path = "/workspaces/gen3-kro"

  tags = {
    Terraform = "true"
    Cluster   = "gen3-kro-hub"
  }
}

# Output: Role ARN = arn:aws:iam::123456789012:role/gen3-kro-hub-addon-aws-load-balancer-controller
```

### ArgoCD with Cross-Account Access

```hcl
module "argocd" {
  source = "./modules/pod-identity"

  service_type = "argocd"
  service_name = "application-controller"
  context      = "hub"

  cluster_name    = "gen3-kro-hub"
  namespace       = "argocd"
  service_account = "argocd-application-controller"

  # Add cross-account assume role policy
  cross_account_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::111111111111:role/spoke1-argocd-managed",
          "arn:aws:iam::222222222222:role/spoke2-argocd-managed"
        ]
      }
    ]
  })

  repo_root_path = "/workspaces/gen3-kro"

  tags = {
    Terraform = "true"
    Cluster   = "gen3-kro-hub"
  }
}
```

### Spoke Context (ACK in Spoke Cluster)

```hcl
module "spoke_ack_s3" {
  source = "./modules/pod-identity"

  service_type = "ack"
  service_name = "s3"
  context      = "spoke1"  # Will look for context-specific policies

  cluster_name    = "gen3-kro-spoke1"
  namespace       = "ack-system"
  service_account = "ack-s3-controller"

  repo_root_path = "/workspaces/gen3-kro"

  tags = {
    Terraform = "true"
    Spoke     = "spoke1"  # This overrides context variable
    Cluster   = "gen3-kro-spoke1"
  }
}

# Looks for policies in:
# 1. iam/ack/spoke1/s3/recommended_inline_policy.json (context-specific)
# 2. iam/ack/hub/s3/recommended_inline_policy.json (fallback)
```

### Custom Service with Inline Policy

```hcl
module "custom_service" {
  source = "./modules/pod-identity"

  service_type = "custom"
  service_name = "my-app-controller"

  cluster_name    = "gen3-kro-hub"
  namespace       = "my-app"
  service_account = "my-app-controller"

  # Provide custom inline policy
  custom_inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::my-bucket/*"
      }
    ]
  })

  # Add AWS managed policies
  custom_managed_arns = {
    cloudwatch = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }

  tags = {
    Terraform = "true"
    Cluster   = "gen3-kro-hub"
  }
}
```

### Using External Git Repository for Policies

```hcl
module "ack_ec2_git" {
  source = "./modules/pod-identity"

  service_type = "ack"
  service_name = "ec2"

  cluster_name    = "gen3-kro-hub"
  namespace       = "ack-system"
  service_account = "ack-ec2-controller"

  # Load policies from Git repository
  iam_policy_repo_url  = "https://github.com/myorg/iam-policies.git"
  iam_policy_branch    = "main"
  iam_policy_base_path = "iam"

  tags = {
    Terraform = "true"
    Cluster   = "gen3-kro-hub"
  }
}
```

## Policy Loading Behavior

### Filesystem Hierarchy

```
iam/
├── ack/                                    # service_type = "ack"
│   ├── hub/                                # context = "hub"
│   │   ├── iam/                            # service_name = "iam"
│   │   │   ├── recommended_inline_policy.json
│   │   │   ├── override.json               # Optional context override
│   │   │   └── managed_arns.txt            # Optional managed ARNs
│   │   ├── ec2/
│   │   └── s3/
│   └── spoke1/                             # context = "spoke1"
│       └── s3/
│           ├── recommended_inline_policy.json
│           └── override.json               # Spoke-specific overrides
├── addon/                                  # service_type = "addon"
│   └── hub/
│       └── aws-load-balancer-controller/
│           ├── recommended_inline_policy.json
│           └── managed_arns.txt
├── argocd/                                 # service_type = "argocd"
│   └── hub/
│       └── application-controller/
│           └── recommended_inline_policy.json
└── custom/                                 # service_type = "custom"
    └── hub/
        └── my-service/
            └── recommended_inline_policy.json
```

### Context Fallback Logic

The module uses a fallback mechanism when looking for context-specific policies:

1. **Primary Path**: `iam/{service_type}/{context}/{service_name}/`
2. **Fallback Path**: `iam/{service_type}/hub/{service_name}/`

**Example:** For `spoke1` context:
```
Search order:
1. iam/ack/spoke1/s3/recommended_inline_policy.json  ← Check first
2. iam/ack/hub/s3/recommended_inline_policy.json     ← Fallback if not found
```

This allows you to:
- Share common policies across all contexts (place in `hub/`)
- Override specific policies for individual contexts (place in `spoke1/`, `spoke2/`, etc.)

### Policy Merging

The module merges policies from multiple sources:

1. **Source Policies** (inline):
   - `recommended_inline_policy.json` from filesystem
   - OR `custom_inline_policy` variable

2. **Override Policies**:
   - `override.json` from context-specific path
   - Replaces portions of the source policy

3. **Cross-Account Policies**:
   - `cross_account_policy_json` variable
   - Merged with source policies

4. **Managed ARNs**:
   - `managed_arns.txt` from filesystem
   - OR `custom_managed_arns` variable
   - Merged with `additional_policy_arns` variable

## Input Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `service_type` | `string` | Type of service: `ack`, `addon`, `argocd`, or `custom` |
| `service_name` | `string` | Name of the service (e.g., `iam`, `aws-load-balancer-controller`) |
| `cluster_name` | `string` | Name of the EKS cluster |
| `namespace` | `string` | Kubernetes namespace for the service account |
| `service_account` | `string` | Kubernetes service account name |

### Policy Loading Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `context` | `string` | `"hub"` | Context for policy loading (hub or spoke alias) |
| `repo_root_path` | `string` | `""` | Local filesystem path to repository root |
| `iam_policy_repo_url` | `string` | `""` | Git repository URL for policies |
| `iam_policy_branch` | `string` | `"main"` | Git branch to use |
| `iam_policy_base_path` | `string` | `"iam"` | Base path within repository |

### Custom Policy Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `custom_inline_policy` | `string` | `null` | Custom inline policy JSON (overrides filesystem) |
| `custom_managed_arns` | `map(string)` | `{}` | Map of managed policy ARNs (overrides filesystem) |
| `additional_policy_arns` | `map(string)` | `{}` | Additional managed ARNs to merge |
| `cross_account_policy_json` | `string` | `null` | Cross-account policy JSON to merge |

### Other Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create` | `bool` | `true` | Whether to create the pod identity |
| `trust_policy_conditions` | `list(any)` | `[]` | Additional IAM trust policy conditions |
| `tags` | `map(string)` | `{}` | Tags to apply to all resources |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `role_arn` | `string` | ARN of the IAM role |
| `role_name` | `string` | Name of the IAM role |
| `role_unique_id` | `string` | Unique ID of the IAM role |
| `policy_arn` | `string` | ARN of the inline policy (if created) |
| `policy_name` | `string` | Name of the inline policy (if created) |
| `associations` | `map(any)` | Map of pod identity associations |
| `policy_source` | `string` | Source of policies: `filesystem`, `custom`, or `none` |

## IAM Role Naming Convention

Roles are named using the pattern: `{cluster_name}-{service_type}-{service_name}`

**Examples:**
- `gen3-kro-hub-ack-iam`
- `gen3-kro-hub-addon-aws-load-balancer-controller`
- `gen3-kro-hub-argocd-application-controller`
- `gen3-kro-spoke1-ack-s3`

## Migration from Legacy Modules

This module replaces three previous modules:

### From `ack-enhanced-pod-identity`

**Before:**
```hcl
module "ack" {
  source = "./modules/ack-enhanced-pod-identity"

  cluster_name = "gen3-kro-hub"
  services     = ["iam", "ec2", "s3"]
  namespace    = "ack-system"

  repo_root_path = "/workspaces/gen3-kro"
}
```

**After:**
```hcl
module "ack_iam" {
  source = "./modules/pod-identity"

  service_type    = "ack"
  service_name    = "iam"
  cluster_name    = "gen3-kro-hub"
  namespace       = "ack-system"
  service_account = "ack-iam-controller"
  repo_root_path  = "/workspaces/gen3-kro"
}

module "ack_ec2" {
  source = "./modules/pod-identity"

  service_type    = "ack"
  service_name    = "ec2"
  cluster_name    = "gen3-kro-hub"
  namespace       = "ack-system"
  service_account = "ack-ec2-controller"
  repo_root_path  = "/workspaces/gen3-kro"
}

module "ack_s3" {
  source = "./modules/pod-identity"

  service_type    = "ack"
  service_name    = "s3"
  cluster_name    = "gen3-kro-hub"
  namespace       = "ack-system"
  service_account = "ack-s3-controller"
  repo_root_path  = "/workspaces/gen3-kro"
}
```

### From `addons-pod-identities`

**Before:**
```hcl
module "addons" {
  source = "./modules/addons-pod-identities"

  cluster_name = "gen3-kro-hub"
  addons = {
    aws_load_balancer_controller = {
      enabled = true
    }
  }
}
```

**After:**
```hcl
module "addon_alb" {
  source = "./modules/pod-identity"

  service_type    = "addon"
  service_name    = "aws-load-balancer-controller"
  cluster_name    = "gen3-kro-hub"
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  repo_root_path  = "/workspaces/gen3-kro"
}
```

### From `argocd-pod-identity`

**Before:**
```hcl
module "argocd_pod_identity" {
  source = "./modules/argocd-pod-identity"

  cluster_name = "gen3-kro-hub"
  namespace    = "argocd"

  spoke_accounts = {
    spoke1 = "111111111111"
    spoke2 = "222222222222"
  }
}
```

**After:**
```hcl
module "argocd" {
  source = "./modules/pod-identity"

  service_type    = "argocd"
  service_name    = "application-controller"
  cluster_name    = "gen3-kro-hub"
  namespace       = "argocd"
  service_account = "argocd-application-controller"

  cross_account_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = [
        "arn:aws:iam::111111111111:role/spoke1-argocd-managed",
        "arn:aws:iam::222222222222:role/spoke2-argocd-managed"
      ]
    }]
  })

  repo_root_path = "/workspaces/gen3-kro"
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |

## Providers

This module uses the `terraform-aws-modules/eks-pod-identity/aws` module (version ~> 1.4.0) which requires:
- AWS Provider >= 5.0

## Dependencies

- `../iam-policy` - IAM policy loading module

## Limitations

1. **Single Association**: Each module instance creates one pod identity association. For multiple clusters, create multiple module instances.
2. **Context Detection**: Context is determined by `tags.Spoke` if present, otherwise uses the `context` variable.
3. **Policy Priority**: Custom policies override filesystem policies. Once you provide `custom_inline_policy` or `custom_managed_arns`, the filesystem loader is bypassed.

## Troubleshooting

### No Policies Found

**Issue:** Module creates role but no policies attached.

**Cause:** Policy files not found in expected location.

**Solution:** Check policy path:
```bash
# Expected path for ACK IAM service in hub context:
ls -la iam/ack/hub/iam/recommended_inline_policy.json

# Verify module output:
terraform output -json | jq '.policy_source.value'
```

### Context Not Detected

**Issue:** Spoke-specific policies not loading.

**Cause:** Tags not set correctly.

**Solution:** Ensure `tags.Spoke` is set:
```hcl
tags = {
  Spoke = "spoke1"  # This sets context to "spoke1"
}
```

### Role Name Conflicts

**Issue:** Role already exists error.

**Cause:** Role name collision (same cluster, service_type, and service_name).

**Solution:** Use different `service_name` values or check existing roles:
```bash
aws iam list-roles | grep "gen3-kro-hub-ack-"
```

## Related Modules

- `iam-policy` - IAM policy loader (used internally)
- `terraform-aws-modules/eks-pod-identity/aws` - Upstream EKS pod identity module

## License

Apache-2.0 License
