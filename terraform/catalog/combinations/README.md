# Terraform Combinations

Provider-specific infrastructure compositions that combine multiple modules into deployable patterns for hub/control-plane (csoc) and spoke environments.

## Purpose

Combinations bridge the gap between granular modules and environment-specific deployments. Each combination represents a complete infrastructure stack for a specific role (csoc or spoke) on a specific cloud provider (AWS, Azure, GCP).

**Key characteristics:**
- **Multi-module orchestration**: Compose VPC, cluster, IAM, and GitOps modules into a single Terraform root
- **Provider-specific logic**: Handle cloud-specific requirements (e.g., AWS VPC peering, Azure VNET integration, GCP shared VPC)
- **Input normalization**: Accept standardized variables from Terragrunt units and map them to module-specific inputs
- **Output aggregation**: Export critical identifiers (cluster endpoints, IAM role ARNs) for downstream dependencies

## Directory Structure

```
combinations/
├── csoc/          # Hub/control-plane combinations
│   ├── aws/       # AWS csoc (VPC + EKS + Pod Identity + ArgoCD + spoke ConfigMap)
│   ├── azure/     # Azure csoc (VNET + AKS + Managed Identity + ArgoCD)
│   └── gcp/       # GCP csoc (VPC + GKE + Workload Identity + ArgoCD)
└── spoke/         # Spoke environment combinations
    ├── aws/       # AWS spoke (VPC + EKS + Pod Identity + spoke role trust)
    ├── azure/     # Azure spoke (VNET + AKS + Managed Identity + service principal)
    └── gcp/       # GCP spoke (VPC + GKE + Workload Identity + service account)
```

## Combination Patterns

### csoc/aws

Provisions a complete AWS hub environment:

**Modules composed:**
1. `aws-vpc`: VPC with public/private subnets, NAT gateways
2. `aws-eks-cluster`: EKS control plane and managed node groups
3. `iam-policy`: Load IAM policies from `iam/aws/<env>/<service>/`
4. `aws-pod-identity`: Create IAM roles for hub addon controllers (ACK, ExternalSecrets)
5. `argocd`: Install ArgoCD and deploy bootstrap ApplicationSets
6. `spokes-configmap`: Generate ConfigMap with spoke IAM role ARNs (if `enable_multi_acct = true`)

**Critical variables** (passed from Terragrunt unit):
| Variable | Purpose | Example |
|----------|---------|---------|
| `catalog_path` | **Anchor**: Path to catalog root for nested module resolution | `"../../catalog"` |
| `addon_configs` | Map of addon names to configuration (namespace, IRSA annotations) | `{ "ack-s3" = { namespace = "ack-system" } }` |
| `spoke_arn_inputs` | Nested map of spoke alias → controller → ARN (from spoke deployments) | `{ spoke1 = { ack-s3 = { role_arn = "arn:..." } } }` |
| `enable_multi_acct` | Enable spoke ConfigMap and cross-account IAM policies | `true` |

**Terragrunt usage example:**

```hcl
# In terraform/units/csoc/terragrunt.hcl
terraform {
  source = "${values.catalog_path}//combinations/csoc/${values.csoc_provider}"
}

inputs = {
  catalog_path      = "${get_repo_root()}/terraform/catalog"
  cluster_name      = "gen3-hub"
  addon_configs     = {
    ack-s3 = { namespace = "ack-system" }
    external-secrets = { namespace = "external-secrets" }
  }
  spoke_arn_inputs  = dependency.spokes.outputs.spoke_arns
  enable_multi_acct = true
}
```

### spoke/aws

Provisions an AWS spoke environment with trust relationship to hub:

**Modules composed:**
1. `aws-vpc`: Isolated VPC for spoke workloads
2. `aws-eks-cluster`: EKS cluster for Gen3 services
3. `iam-policy`: Load spoke-specific IAM policies
4. `aws-pod-identity`: Create IAM roles for spoke controllers
5. `aws-spoke-role`: Create IAM roles assumable by hub Pod Identity roles (enables cross-account resource management)

**Critical variables:**
| Variable | Purpose |
|----------|---------|
| `spoke_alias` | Spoke environment identifier (e.g., `spoke1`, `prod-gen3`) |
| `csoc_account_id` | AWS account ID of hub cluster (for IAM trust policy) |
| `csoc_pod_identity_arns` | Map of hub controller names → Pod Identity role ARNs |

**Terragrunt usage example:**

```hcl
# In terraform/units/spokes/terragrunt.hcl
terraform {
  source = "${values.catalog_path}//combinations/spoke/${values.spoke_provider}"
}

inputs = {
  spoke_alias             = "spoke1"
  csoc_account_id         = "123456789012"
  csoc_pod_identity_arns  = dependency.csoc.outputs.pod_identity_role_arns
  addon_configs           = {
    ack-s3 = { namespace = "ack-system" }
  }
}
```

## Provider-Specific Notes

### AWS
- **Cross-account access**: Spoke IAM roles use `AssumeRole` trust policies referencing hub Pod Identity role ARNs
- **VPC peering**: Not automated; configure manually if spokes need direct communication
- **EKS authentication**: Combinations generate Kubernetes provider configs using `aws eks get-token` exec plugin

### Azure
- **Managed Identity binding**: Combinations create federated credentials linking AKS OIDC issuer to Azure AD service principals
- **VNET integration**: Spokes can peer to hub VNET via separate `azurerm_virtual_network_peering` resources (not included in combinations)
- **AKS authentication**: Combinations use `azurerm` provider with `kubelogin` exec plugin for AAD authentication

### GCP
- **Workload Identity**: Combinations bind GCP service accounts to Kubernetes service accounts via `iam.workloadIdentityUser` role
- **Shared VPC**: Spokes can attach to hub VPC as service projects (requires `compute.networkUser` IAM binding on host project)
- **GKE authentication**: Combinations use `gcloud container clusters get-credentials` exec plugin

## Extending Combinations

To add resources to a combination:

1. Edit `combinations/<role>/<provider>/main.tf`
2. Add module invocation with appropriate `depends_on` for ordering
3. Update `variables.tf` to accept new inputs from Terragrunt unit
4. Export new outputs in `outputs.tf` (if needed by downstream dependencies)
5. Test locally with `terragrunt validate` and `terragrunt plan`

Example: Adding AWS OpenSearch to csoc/aws:

```hcl
# In combinations/csoc/aws/main.tf
module "opensearch" {
  source = "../../../modules/aws-opensearch"

  domain_name = "${var.cluster_name}-opensearch"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnets

  depends_on = [module.eks_cluster]
}
```

Update `iam/aws/<env>/opensearch/policy.json` with required IAM permissions, then reference in `variables.tf`:

```hcl
variable "opensearch_iam_policy" {
  type = string
}
```

See [`docs/guides/customization.md`](../../../docs/guides/customization.md) for complete workflows.

---
**Last updated:** 2025-10-28
