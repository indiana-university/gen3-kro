# Generic IAM Policy Module

Universal IAM policy loader for EKS Pod Identities supporting ACK, addons, ArgoCD, and custom services.

## Features

- Loads IAM policies from Git repositories or local filesystem
- Supports context-specific policies (hub vs spoke)
- Handles inline policies, managed policy ARNs, and override policies
- Falls back from spoke-specific to hub policies
- Allows custom policy injection

## Policy File Structure

```
{iam_policy_base_path}/gen3-kro/{context}/{service_type_folder}/{service_name}/
├── source-policy-inline.json    # Inline IAM policy document
├── source-policy-arn.json        # JSON map of managed policy ARNs
└── overridepolicy.json           # Override policy document
```

### Service Type Folders
- `acks/` - For ACK controllers (e.g., `acks/s3/`, `acks/iam/`)
- `addons/` - For EKS addons (e.g., `addons/ebs-csi/`, `addons/cluster-autoscaler/`)
- `argocd/` - For ArgoCD (e.g., `argocd/`)
- `customs/` - For custom services

### Context
- `hub` - Hub cluster policies
- `{spoke_alias}` - Spoke-specific policies (falls back to hub if not found)

## Usage

```hcl
module "iam_policy" {
  source = "../../modules/iam-policy"

  service_type         = "ack"  # or "addon", "argocd", "custom"
  service_name         = "s3"
  context              = "hub"  # or spoke alias
  iam_policy_repo_url  = "git::https://github.com/org/repo.git"
  iam_policy_branch    = "main"
  iam_policy_base_path = "iam"
  repo_root_path       = ""  # Use when loading from local filesystem
}

# Use outputs
inline_policy = module.iam_policy.inline_policy_document
managed_arns  = module.iam_policy.managed_policy_arns
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| service_type | Service type: ack, addon, argocd, custom | string | - | yes |
| service_name | Service name (e.g., s3, ebs-csi) | string | - | yes |
| context | Deployment context (hub or spoke alias) | string | "hub" | no |
| iam_policy_repo_url | Git URL for IAM policies | string | "" | no |
| iam_policy_branch | Git branch | string | "main" | no |
| iam_policy_base_path | Base path in repo | string | "iam" | no |
| repo_root_path | Local repo root path | string | "" | no |
| custom_inline_policy | Custom inline policy (overrides filesystem) | string | null | no |
| custom_managed_arns | Custom managed ARNs (overrides filesystem) | map(string) | {} | no |
| custom_override_policy | Custom override policy | string | null | no |

## Outputs

| Name | Description |
|------|-------------|
| inline_policy_document | Inline policy document (if any) |
| managed_policy_arns | Map of managed policy ARNs |
| override_policy_documents | List of override policy documents |
| has_inline_policy | Boolean indicating inline policy presence |
| has_managed_policies | Boolean indicating managed policies presence |
| policy_source | Source of policy: filesystem, custom, or none |

## Examples

### ACK Controller
```hcl
module "s3_policy" {
  source = "../../modules/iam-policy"

  service_type = "ack"
  service_name = "s3"
  context      = "hub"

  iam_policy_repo_url  = "git::https://github.com/org/repo.git"
  iam_policy_branch    = "main"
  iam_policy_base_path = "iam"
}
```

### EKS Addon
```hcl
module "ebs_csi_policy" {
  source = "../../modules/iam-policy"

  service_type = "addon"
  service_name = "ebs-csi"
  context      = "hub"

  iam_policy_repo_url  = "git::https://github.com/org/repo.git"
  iam_policy_branch    = "main"
  iam_policy_base_path = "iam"
}
```

### ArgoCD
```hcl
module "argocd_policy" {
  source = "../../modules/iam-policy"

  service_type = "argocd"
  service_name = "argocd"
  context      = "hub"

  repo_root_path = "${path.root}/../../../.."
  iam_policy_base_path = "iam"
}
```

### With Custom Policy
```hcl
module "custom_policy" {
  source = "../../modules/iam-policy"

  service_type = "custom"
  service_name = "my-service"
  context      = "hub"

  custom_inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = ["arn:aws:s3:::my-bucket/*"]
    }]
  })
}
```
