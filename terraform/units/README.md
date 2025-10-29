# Terraform Units

Terragrunt wrappers that transform catalog combinations into deployable infrastructure units with provider configuration, backend state management, and dependency orchestration.

## Purpose

Units sit between catalog combinations and live environment stacks, providing:

- **Backend generation**: Auto-create provider-specific Terraform backend configuration (S3, Azure Storage, GCS)
- **Provider configuration**: Generate exec-based authentication for Kubernetes/Helm providers using cluster outputs
- **Input mapping**: Bridge environment configuration (`live/.../terragrunt.stack.hcl`) to combination variables
- **Dependency resolution**: Define inter-unit dependencies (e.g., spokes depend on csoc for IAM trust relationships)

Units are invoked by Terragrunt stacks via `dependency` blocks, creating a directed acyclic graph (DAG) of infrastructure deployments.

## Unit Structure

```
units/
├── csoc/
│   └── terragrunt.hcl   # Hub/control-plane unit (VPC, cluster, ArgoCD, spoke ConfigMap)
└── spokes/
    └── terragrunt.hcl   # Spoke environment unit (VPC, cluster, cross-account IAM roles)
```

Each `terragrunt.hcl` contains:
1. `terraform.source`: Path to catalog combination
2. `generate` blocks: Backend and provider configurations
3. `inputs`: Variable mapping from stack locals
4. `dependencies`: References to other units (if needed)

## Unit Patterns

### Backend Generation

Terragrunt dynamically generates `backend.tf` based on the provider type, reading configuration from `values.csoc_provider` or `values.spoke_provider`.

**Example: AWS S3 backend** (from `units/csoc/terragrunt.hcl`):

```hcl
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = (
    values.csoc_provider == "aws" ? <<EOF
terraform {
  backend "s3" {
    bucket         = "${values.state_bucket}"
    key            = "${values.csoc_alias}/units/csoc/terraform.tfstate"
    region         = "${values.region}"
    encrypt        = true
    dynamodb_table = "${values.state_locks_table}"
  }
}
EOF
    : ""
  )
}
```

**Azure backend** (same pattern):
```hcl
values.csoc_provider == "azure" ? <<EOF
terraform {
  backend "azurerm" {
    storage_account_name = "${values.state_storage_account}"
    container_name       = "${values.state_container}"
    key                  = "${values.csoc_alias}/units/csoc/terraform.tfstate"
  }
}
EOF
```

**GCP backend**:
```hcl
values.csoc_provider == "gcp" ? <<EOF
terraform {
  backend "gcs" {
    bucket = "${values.state_bucket}"
    prefix = "${values.csoc_alias}/units/csoc"
  }
}
EOF
```

### Provider Exec Blocks

Units generate Kubernetes and Helm provider configurations using `exec` plugins for authentication, leveraging cluster outputs from combinations.

**Example: AWS EKS authentication** (from `units/csoc/terragrunt.hcl`):

```hcl
generate "csoc_kubernetes_provider" {
  path      = "kubernetes-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = (values.enable_k8s_cluster && values.csoc_provider == "aws" ? <<-EOF
provider "kubernetes" {
  host                   = module.csoc.cluster_endpoint
  cluster_ca_certificate = base64decode(module.csoc.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", module.csoc.cluster_name,
      "--region", "${values.region}"
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.csoc.cluster_endpoint
    cluster_ca_certificate = base64decode(module.csoc.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", module.csoc.cluster_name,
        "--region", "${values.region}"
      ]
    }
  }
}
EOF
    : ""
  )
}
```

**Azure AKS authentication** uses `kubelogin`:
```hcl
exec {
  api_version = "client.authentication.k8s.io/v1beta1"
  command     = "kubelogin"
  args = [
    "get-token",
    "--login", "azurecli",
    "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"  # Azure Kubernetes Service AAD Server
  ]
}
```

**GCP GKE authentication** uses `gcloud`:
```hcl
exec {
  api_version = "client.authentication.k8s.io/v1beta1"
  command     = "gcloud"
  args = [
    "container", "clusters", "get-credentials",
    module.csoc.cluster_name,
    "--region", "${values.region}",
    "--project", "${values.project_id}"
  ]
}
```

### Input Mapping

Units accept configuration from `live/.../terragrunt.stack.hcl` via the `values` object (implicitly provided by Terragrunt stacks).

**Example input block** (from `units/csoc/terragrunt.hcl`):

```hcl
inputs = {
  catalog_path = values.catalog_path

  # Provider configuration
  csoc_provider = values.csoc_provider
  tags          = values.tags
  cluster_name  = values.cluster_name

  # VPC configuration
  enable_vpc           = values.enable_vpc
  vpc_name             = values.vpc_name
  vpc_cidr             = values.vpc_cidr
  availability_zones   = values.availability_zones
  private_subnet_cidrs = values.private_subnet_cidrs
  public_subnet_cidrs  = values.public_subnet_cidrs

  # Cluster configuration
  enable_k8s_cluster = values.enable_k8s_cluster
  cluster_version    = values.cluster_version

  # Multi-account configuration
  enable_multi_acct = values.enable_multi_acct
  spoke_arn_inputs  = values.spoke_arn_inputs

  # Addon configuration
  addon_configs = values.addon_configs

  # ArgoCD configuration
  enable_argocd      = values.enable_argocd
  argocd_config      = values.argocd_config
  argocd_outputs_dir = values.argocd_outputs_dir
}
```

The `values` object is populated from `locals` defined in `live/.../terragrunt.stack.hcl`, which parses `secrets.yaml`.

### Dependency Orchestration

Units can reference outputs from other units using Terragrunt's `dependency` block. This is used in spoke units to obtain hub IAM role ARNs for trust policies.

**Example: Spoke depending on csoc** (conceptual, not currently in spokes unit):

```hcl
dependency "csoc" {
  config_path = "../csoc"
}

inputs = {
  csoc_account_id        = dependency.csoc.outputs.account_id
  csoc_pod_identity_arns = dependency.csoc.outputs.pod_identity_role_arns
}
```

In practice, this dependency is resolved at the stack level (`live/.../terragrunt.stack.hcl`) rather than in individual units.

## ArgoCD Outputs

The csoc unit generates ArgoCD bootstrap manifests and writes them to `argocd_outputs_dir` (default: `./outputs/argo`). These files are used by the `argocd` module to deploy ApplicationSets referencing the `argocd/` directory structure.

**Generated files:**
- `bootstrap-apps.yaml`: App-of-apps ApplicationSet
- `cluster-secret.yaml`: ArgoCD cluster definition for hub/spoke registration

## Testing Units

Test a unit in isolation:

```bash
cd terraform/units/csoc
terragrunt init
terragrunt validate
terragrunt plan -var-file=test-values.tfvars  # Requires mock values for all inputs
```

For full stack testing, use live environments (see [`live/README.md`](../../live/README.md)).

## Unit Lifecycle

1. **Initialization**: `terragrunt init` creates `.terragrunt-cache/` with combination source and generated files
2. **Planning**: `terragrunt plan` shows resource changes, reads backend state
3. **Application**: `terragrunt apply` provisions resources, writes state to backend
4. **Output extraction**: `terragrunt output` retrieves combination outputs for dependency resolution

Units are typically invoked via `terragrunt <command> --all` at the stack level, which handles dependency ordering automatically.

---
**Last updated:** 2025-10-28
