# ArgoCD GitOps Configuration

## Overview

This directory contains the declarative GitOps configuration for a multi-cluster EKS platform. ArgoCD on the CSOC cluster reconciles this directory tree to provision spoke infrastructure and deploy workloads via KRO + ACK controllers.

## Directory Structure

```
argocd/
├── bootstrap/                      # Entry-point ApplicationSets (Terraform-created bootstrap reads this)
│   ├── csoc-addons.yaml            #   CSOC addon ApplicationSet (wave -20)
│   ├── ack-multi-acct.yaml         #   ACK CARM multi-account ApplicationSet (wave 5)
│   └── fleet-instances.yaml        #   KRO infrastructure + app + test instances (wave 30)
├── addons/                         # Addon value files (merged via multi-source Helm)
│   └── addons.yaml                 #   Single file: EKS CSOC addons + Kind local addons
├── charts/                         # Helm charts consumed by ApplicationSets
│   ├── application-sets/           #   Meta-chart: generates per-addon ApplicationSets
│   ├── multi-acct/                 #   ACK CARM multi-account Helm chart
│   └── resource-groups/            #   KRO ResourceGraphDefinition manifests
├── cluster-fleet/                  # Per-cluster override values (highest precedence)
│   ├── spoke1/
│   │   ├── infrastructure/         #   KRO instance definitions (one YAML file per tier)
│   │   ├── cluster-resources/      #   Cluster-level resource values (1 per cluster)
│   │   ├── applications/           #   Gen3 application values (Helm2 instances)
│   │   └── tests/                  #   KRO capability test instances
│   └── _example/                   #   Template for new spoke directories
└── local-kind/                     # Kind cluster instance definitions
    └── test/                       #   Local test: infra, apps, cluster-resources, tests
```

## Reconciliation Chain

ArgoCD reconciliation follows this chain, enforced by sync waves:

```
Terraform creates:
  └── Bootstrap ApplicationSet (helm_release)
        └── Reads argocd/bootstrap/ directory
              ├── csoc-addons.yaml → csoc-addons AppSet (wave -20)
              │                      └── KRO (wave -30)
              │                      └── ACK controllers (wave 1)
              │                      └── KRO RGDs (wave 10)
              │                      └── External Secrets (wave 15)
              │
              ├── ack-multi-acct.yaml → ack-multi-acct AppSet (wave 5)
              │                         └── CARM namespaces + IAMRoleSelectors
              │
              └── fleet-instances.yaml → fleet-instances AppSet (wave 30)
                                         └── KRO instances (infra + apps + tests)
```

## Sync Wave Ordering

| Wave | What | Why |
|------|------|-----|
| -30 | KRO controller | Must be running before RGDs can be applied |
| -20 | CSOC addons ApplicationSet | Installs ACK controllers and resource groups |
| 1 | ACK controllers (self-managed) | Must exist before KRO instances reference them |
| 5 | ACK multi-account (CARM) | Namespace + IAMRoleSelector for each spoke |
| 10 | KRO ResourceGraphDefinitions | CRDs must be registered before instances |
| 15 | External Secrets Operator | Credential provider for workloads |
| 30 | Fleet instances (KRO) | Infrastructure, app, and test CRs depend on all controllers |

## Values Merge Priority (Last Wins)

### Addon Values
1. `charts/application-sets/` defaults (lowest)
2. `addons/addons.yaml`
3. `cluster-fleet/<cluster>/addons.yaml` **(highest — wins)**

The merge uses multi-source Helm with ref-based value files:
```yaml
sources:
  - ref: values
    repoURL: '{{.metadata.annotations.addons_repo_url}}'
    targetRevision: '{{.metadata.annotations.addons_repo_revision}}'
  - repoURL: '{{.metadata.annotations.addons_repo_url}}'
    path: '{{.metadata.annotations.addons_repo_basepath}}charts/{{.values.addonChart}}'
    helm:
      ignoreMissingValueFiles: true
      valueFiles:
        - $values/{{.metadata.annotations.addons_config_path}}
        - $values/{{.metadata.annotations.addons_repo_basepath}}cluster-fleet/{{ .name }}/addons.yaml
```

## Cluster Generator & Label/Annotation Contract

ApplicationSets use the **cluster generator** with label selectors. The ArgoCD cluster secret (created by Terraform `argocd-bootstrap` module) carries:

### Labels (used for `matchLabels`)
| Label | Values | Purpose |
|-------|--------|---------|
| `fleet_member` | `control-plane`, `spoke` | Target cluster type |
| `environment` | `control-plane`, `dev`, `prod` | Environment classification |
| `ack_management_mode` | `self_managed`, `aws_managed` | ACK controller mode |
| `enable_external_secrets` | `true` | ESO feature flag |
| `enable_kro_eks_rgs` | `true` | KRO RGD feature flag |
| `enable_multi_acct` | `true` | Multi-account mode |

### Annotations (used as template parameters)
| Annotation | Example | Purpose |
|------------|---------|---------|
| `addons_repo_url` | `https://github.iu.edu/.../eks-cluster-mgmt.git` | Git repo for addon configs |
| `addons_repo_revision` | `main` | Branch/tag |
| `addons_repo_basepath` | `argocd/` | Path prefix in repo |
| `fleet_repo_url` | Same repo | Git repo for fleet configs |
| `fleet_repo_revision` | `main` | Branch/tag |
| `aws_account_id` | `<CSOC_ACCOUNT_ID>` | CSOC account ID |
| `aws_cluster_name` | `{csoc_alias}-csoc-cluster` | EKS cluster name |
| `aws_region` | `us-east-1` | AWS region |
| `ack_self_managed_role_arn` | `arn:aws:iam::...` | ACK source role for IRSA |

## Chart Details

### application-sets (Core Engine)

Generates one ApplicationSet per enabled addon key in values:

```yaml
addon-name:
  enabled: true                    # Required
  syncWave: "1"                    # Required — install order
  chartUrl: "oci://registry..."    # Helm chart URL
  chartName: "chart-name"          # Chart name
  chartVersion: "1.0.0"            # Pinned version
  namespace: "addon-ns"            # Target namespace
  type: manifest                   # Optional — "manifest" for raw YAML dirs
  repoPath: "charts/resource-groups"  # Required if type=manifest
  selectors:                       # Optional — extra label matchers
    ack_management_mode: self_managed
```

### resource-groups

Static KRO `ResourceGraphDefinition` YAML files. Files follow naming: `<tier>-<provider><name>-rg.yaml` (e.g., `00-awsgen3network1-rg.yaml`). Also contains KRO capability test RGDs (`krotest*-rg.yaml`).

### multi-acct

ACK CARM multi-account Helm chart. Creates per-spoke namespaces and IAMRoleSelectors for cross-account resource management.

## CSOC Addons (`addons/addons.yaml`)

The addons file contains both EKS CSOC and Kind local addons, distinguished by `cluster_type` selector (`eks` vs `kind`).

### EKS CSOC Addons

| Addon | Wave | Type | Purpose |
|-------|------|------|---------|
| `self-managed-kro` | -30 | Helm (OCI) | KRO controller — must be first |
| `ack-*-controller` (18x) | 1 | Helm (OCI) | ACK: acm, cloudtrail, cloudwatchlogs, ec2, efs, eks, elasticache, iam, kms, lambda, opensearchservice, rds, route53, s3, secretsmanager, sns, sqs, wafv2 |
| `kro-eks-rgs` | 10 | manifest | KRO ResourceGraphDefinitions |
| `external-secrets` | 15 | Helm | External Secrets Operator |

### Kind Local Addons

| Addon | Wave | Type | Purpose |
|-------|------|------|---------|
| `self-managed-kro-kind` | -30 | Helm | KRO controller |
| `kro-csoc-rgs-kind` | 10 | manifest | KRO ResourceGraphDefinitions |
| `ack-*-kind` (13x) | 1 | Helm (OCI) | ACK: acm, ec2, eks, elasticache, iam, kms, opensearchservice, rds, route53, s3, secretsmanager, sqs, wafv2 |

## Cluster Fleet (`cluster-fleet/<cluster>/`)

Each subdirectory must match a spoke alias defined in `spoke_account_ids` in `config/shared.auto.tfvars.json`. Files:

| File/Dir | Purpose |
|----------|---------|
| `addons.yaml` | Override addon values (empty `{}` = accept defaults) |
| `infrastructure/` | KRO instance definitions (one standalone YAML file per tier) |
| `cluster-resources/` | Cluster-level resource values (1 per cluster) |
| `applications/` | Gen3 application values (Helm2 instances) |
| `tests/` | KRO capability test instances |

The `local-kind/test/` directory mirrors this structure for Kind clusters.

## Conventions

- All ApplicationSets use `goTemplate: true` (Go template syntax required)
- Bootstrap directory files must be valid Kubernetes manifests (not Helm values)
- Addon keys use kebab-case: `external-secrets`, `self-managed-kro`
- Cluster fleet directories must match spoke aliases from `shared.auto.tfvars.json` (`spoke_account_ids` keys)
- Empty YAML files must contain `{}` (not blank)
- `ignoreMissingValueFiles: true` — optional overlays don't cause errors

## Validation

```bash
# Validate charts render correctly
helm template argocd/charts/application-sets/
helm template argocd/charts/resource-groups/

# Validate with values
helm template argocd/charts/application-sets/ -f argocd/addons/addons.yaml

# Validate KRO instance YAML files directly
kubectl apply --dry-run=client -f argocd/cluster-fleet/spoke1/infrastructure/
```
