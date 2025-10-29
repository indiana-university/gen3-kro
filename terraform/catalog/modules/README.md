# Terraform Modules

Reusable infrastructure primitives for multi-cloud Gen3 deployments. Each module encapsulates a single concern (VPC, Kubernetes cluster, IAM role) and exposes a provider-agnostic or provider-specific interface.

## Module Authoring Standards

All modules follow this standardized documentation format:

### Template Structure

```markdown
# Module Name

## Summary
Brief description (1-2 sentences) of what the module provisions.

## Prerequisites
- Cloud provider requirements (account permissions, quotas)
- Dependencies on other modules or resources
- Required Terraform/provider versions

## Inputs
| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `input_name` | `string` | `"default"` | No | Description with usage notes |

## Outputs
| Name | Type | Description |
|------|------|-------------|
| `output_name` | `string` | Description of exported value |

## Usage
```hcl
module "example" {
  source = "../../modules/module-name"

  required_input = "value"
  optional_input = "override"
}
```

## Notes
- Lifecycle considerations (recreates on change, state sensitivity)
- Tagging strategy
- Known limitations or cloud provider quirks
```

## Key Modules

### aws-eks-cluster

**Summary**: Provisions an EKS cluster with configurable node groups, VPC attachment, and cluster authentication.

**Prerequisites**:
- Existing VPC and subnets (or use `aws-vpc` module)
- IAM permissions for `eks:*`, `ec2:*`, `iam:PassRole`

**Inputs** (anchor variables highlighted):
| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `cluster_name` | `string` | - | Yes | **Anchor**: EKS cluster identifier |
| `cluster_version` | `string` | `"1.33"` | No | Kubernetes version |
| `vpc_id` | `string` | - | Yes | VPC ID for cluster placement |
| `subnet_ids` | `list(string)` | - | Yes | Private subnet IDs for node placement |
| `cluster_endpoint_public_access` | `bool` | `false` | No | Enable public API endpoint |
| `enable_cluster_creator_admin_permissions` | `bool` | `false` | No | Grant admin to creator IAM identity |
| `cluster_compute_config` | `object` | `{}` | No | Node group configurations (instance type, scaling) |

**Outputs**:
| Name | Type | Description |
|------|------|-------------|
| `cluster_name` | `string` | EKS cluster name |
| `cluster_endpoint` | `string` | Kubernetes API endpoint |
| `cluster_certificate_authority_data` | `string` | Base64-encoded CA certificate |
| `cluster_arn` | `string` | EKS cluster ARN |

**Usage**:
```hcl
module "eks_cluster" {
  source = "../../modules/aws-eks-cluster"

  cluster_name                             = "gen3-hub"
  cluster_version                          = "1.33"
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  cluster_compute_config = {
    default = {
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size       = 1
      max_size       = 4
    }
  }
}
```

**Notes**:
- Cluster recreation triggers on `cluster_name` or `cluster_version` changes
- Outputs are used by `argocd` module for Kubernetes provider configuration

---

### gcp-workload-identity

**Summary**: Creates a GCP IAM service account and binds it to a Kubernetes service account via Workload Identity for pod-level authentication.

**Prerequisites**:
- GKE cluster with Workload Identity enabled
- Permissions: `iam.serviceAccounts.create`, `iam.serviceAccountKeys.create`

**Inputs**:
| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `service_name` | `string` | - | Yes | **Anchor**: Service identifier (used for SA naming) |
| `namespace` | `string` | `"default"` | No | Kubernetes namespace |
| `project_id` | `string` | - | Yes | GCP project ID |
| `policy_inline_json` | `string` | `null` | No | Inline IAM policy JSON (if not using `policy_arn`) |

**Outputs**:
| Name | Type | Description |
|------|------|-------------|
| `service_account_email` | `string` | GCP service account email |
| `workload_identity_binding` | `string` | Workload Identity binding annotation |

**Usage**:
```hcl
module "workload_identity" {
  source = "../../modules/gcp-workload-identity"

  service_name        = "gen3-metadata"
  namespace           = "gen3"
  project_id          = "my-gcp-project"
  policy_inline_json  = file("${path.root}/../../../iam/gcp/_default/metadata/policy.json")
}
```

**Notes**:
- Kubernetes ServiceAccount must be created separately (typically via ArgoCD addon)
- Workload Identity annotation: `iam.gke.io/gcp-service-account=<service_account_email>`

---

### spokes-configmap

**Summary**: Generates a Kubernetes ConfigMap containing spoke environment metadata (ARNs, identifiers) consumed by hub/csoc cluster controllers.

**Prerequisites**:
- Terraform outputs from spoke deployments (passed via `spoke_arn_inputs` variable)

**Inputs**:
| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `spoke_arn_inputs` | `map(map(string))` | `{}` | Yes | **Anchor**: Map of spoke alias → controller ARNs |
| `configmap_name` | `string` | `"spoke-arns"` | No | ConfigMap name |
| `namespace` | `string` | `"kube-system"` | No | Target namespace |

**Outputs**:
| Name | Type | Description |
|------|------|-------------|
| `configmap_name` | `string` | Created ConfigMap name |

**Usage**:
```hcl
module "spokes_configmap" {
  source = "../../modules/spokes-configmap"

  spoke_arn_inputs = {
    spoke1 = {
      ack-s3 = { role_arn = "arn:aws:iam::123456789012:role/spoke1-ack-s3" }
      ack-rds = { role_arn = "arn:aws:iam::123456789012:role/spoke1-ack-rds" }
    }
    spoke2 = {
      ack-s3 = { role_arn = "arn:aws:iam::987654321098:role/spoke2-ack-s3" }
    }
  }

  namespace = "kube-system"
}
```

**Notes**:
- `spoke_arn_inputs` populated by Terragrunt stack dependency graph (see `live/.../terragrunt.stack.hcl`)

---

## Module Inventory

| Module | Provider | Purpose |
|--------|----------|---------|
| `argocd` | Kubernetes/Helm | Installs ArgoCD and deploys bootstrap ApplicationSets |
| `aws-cross-account-policy` | AWS | Creates IAM policies for cross-account spoke access |
| `aws-eks-cluster` | AWS | Provisions EKS cluster with managed node groups |
| `aws-pod-identity` | AWS | Creates IAM roles for EKS Pod Identity |
| `aws-spoke-role` | AWS | Creates IAM roles for spoke environment access |
| `aws-vpc` | AWS | Provisions VPC with public/private subnets and NAT gateways |
| `azure-aks-cluster` | Azure | Provisions AKS cluster with system/user node pools |
| `azure-managed-identity` | Azure | Creates managed identities for pod workloads |
| `azure-resource-group` | Azure | Creates Azure resource group |
| `azure-spoke-role` | Azure | Creates service principals for spoke access |
| `azure-vnet` | Azure | Provisions Azure virtual network |
| `gcp-gke-cluster` | GCP | Provisions GKE cluster with node pools |
| `gcp-spoke-role` | GCP | Creates service accounts for spoke access |
| `gcp-vpc` | GCP | Provisions GCP VPC network |
| `gcp-workload-identity` | GCP | Binds GCP SA to Kubernetes SA via Workload Identity |
| `iam-policy` | Multi-cloud | Loads JSON policy files from `iam/` directory |
| `spokes-configmap` | Kubernetes | Creates ConfigMap with spoke metadata for hub controllers |

## Extending the Catalog

To add a new module:

1. Create module directory under `modules/<module-name>`
2. Implement `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
3. Document using the template structure above (save as `modules/<module-name>/README.md`)
4. Reference module in appropriate combination (`combinations/csoc/<provider>` or `combinations/spoke/<provider>`)
5. Update IAM policies in `iam/<provider>/_default/<service>/` if module requires cloud permissions

See [`docs/guides/customization.md`](../../../docs/guides/customization.md) for detailed workflows.

---
**Last updated:** 2025-10-26
