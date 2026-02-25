# ArgoCD GitOps Configuration

## Overview

This directory contains the declarative GitOps configuration for a multi-cluster EKS platform. ArgoCD on the CSOC cluster reconciles this directory tree to provision spoke infrastructure and deploy workloads via KRO + ACK controllers.

## Directory Structure

```
argocd/
├── bootstrap/                      # Entry-point ApplicationSets (Terraform-created bootstrap reads this)
│   ├── addons.yaml                 #   csoc-addons (wave -20) + spoke-addons (wave 20) AppSets
│   └── cluster-fleet.yaml          #   fleet AppSet (wave 30)
├── addons/                         # Addon value files (merged via multi-source Helm)
│   ├── csoc/
│   │   └── addons.yaml             #   CSOC addons: KRO, 17x ACK controllers, ESO
│   └── environments/
│       ├── dev/addons.yaml          #   Dev spoke addons
│       └── prod/addons.yaml         #   Prod spoke addons
├── charts/                         # Helm charts consumed by ApplicationSets
│   ├── application-sets/           #   Meta-chart: generates per-addon ApplicationSets
│   ├── instances/                  #   KRO custom resource instance renderer
│   ├── resource-groups/            #   KRO ResourceGraphDefinition manifests
│   └── workloads/                  #   Gen3 application workload chart
└── cluster-fleet/                  # Per-cluster override values (highest precedence)
    ├── spoke1/
    │   ├── addons.yaml             #   Addon overrides for spoke1
    │   ├── infrastructure.yaml     #   KRO instance definitions
    │   └── workload.yaml           #   Application workload values
    └── spoke2/
        ├── addons.yaml
        ├── infrastructure.yaml
        └── workload.yaml
```

## Reconciliation Chain

ArgoCD reconciliation follows this chain, enforced by sync waves:

```
Terraform creates:
  └── Bootstrap ApplicationSet (helm_release)
        └── Reads argocd/bootstrap/ directory
              ├── addons.yaml → csoc-addons AppSet (wave -20)
              │                  └── KRO (wave -30)
              │                  └── ACK controllers (wave 1)
              │                  └── KRO RGDs (wave 10)
              │                  └── External Secrets (wave 15)
              │
              ├── addons.yaml → spoke-addons AppSet (wave 20)
              │                  └── Spoke-specific addons
              │
              └── cluster-fleet.yaml → fleet AppSet (wave 30)
                                       └── KRO instances
                                       └── Workloads
```

## Sync Wave Ordering

| Wave | What | Why |
|------|------|-----|
| -30 | KRO controller | Must be running before RGDs can be applied |
| -20 | CSOC addons ApplicationSet | Installs ACK controllers and resource groups |
| 1 | ACK controllers (self-managed) | Must exist before KRO instances reference them |
| 10 | KRO ResourceGraphDefinitions | CRDs must be registered before instances |
| 15 | External Secrets Operator | Credential provider for workloads |
| 20 | Spoke addons ApplicationSet | Spoke-specific addons after CSOC is ready |
| 30 | Fleet instances / workloads | Infrastructure and apps depend on all controllers |

## Values Merge Priority (Last Wins)

### Addon Values
1. `charts/application-sets/` defaults (lowest)
2. `addons/csoc/addons.yaml` or `addons/environments/<env>/addons.yaml`
3. `cluster-fleet/<cluster>/addons.yaml` **(highest — wins)**

### Infrastructure Values
1. `charts/instances/` defaults (lowest)
2. `cluster-fleet/<cluster>/infrastructure.yaml` **(wins)**

The merge uses multi-source Helm with ref-based value files:
```yaml
sources:
  - ref: addonsValues
    repoURL: '{{.metadata.annotations.addons_repo_url}}'
    path: '{{.metadata.annotations.addons_repo_basepath}}addons/csoc/'
  - ref: clusterValues
    repoURL: '{{.metadata.annotations.fleet_repo_url}}'
    path: '{{.metadata.annotations.fleet_repo_basepath}}cluster-fleet/{{.name}}/'
  - repoURL: '{{.metadata.annotations.addons_repo_url}}'
    chart: application-sets
    helm:
      valueFiles:
        - $addonsValues/addons.yaml
        - $clusterValues/addons.yaml
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
| `addons_repo_revision` | `v2` | Branch/tag |
| `addons_repo_basepath` | `argocd/` | Path prefix in repo |
| `fleet_repo_url` | Same repo | Git repo for fleet configs |
| `fleet_repo_revision` | `v2` | Branch/tag |
| `aws_account_id` | `<CSOC_ACCOUNT_ID>` | CSOC account ID |
| `aws_cluster_name` | `gen3-csoc-dev` | EKS cluster name |
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

### instances

Renders KRO custom resources from `cluster-fleet/<cluster>/infrastructure.yaml`:

```yaml
instances:
  my-environment:
    kind: AwsGen3Infra1Flat        # KRO kind from RGD
    namespace: default
    syncWave: "30"
    spec:                          # Spec per RGD schema
      vpcCIDR: "10.1.0.0/16"
```

### resource-groups

Static KRO `ResourceGraphDefinition` YAML files. Files follow naming: `<provider><name>-rg.yaml`.

### workloads

Gen3 application deployment wrapper (future use).

## CSOC Addons (`addons/csoc/addons.yaml`)

| Addon | Wave | Type | Purpose |
|-------|------|------|---------|
| `self-managed-kro` | -30 | Helm (OCI) | KRO controller — must be first |
| `ack-*-controller` (17x) | 1 | Helm (OCI) | ACK: ec2, eks, iam, rds, s3, route53, etc. |
| `kro-eks-rgs` | 10 | manifest | KRO ResourceGraphDefinitions |
| `external-secrets` | 15 | Helm | External Secrets Operator |

## Cluster Fleet (`cluster-fleet/<cluster>/`)

Each subdirectory must match a spoke alias defined in `spoke_account_ids` in `config/shared.auto.tfvars.json`. Files:

| File | Purpose |
|------|---------|
| `addons.yaml` | Override addon values (empty `{}` = accept defaults) |
| `infrastructure.yaml` | KRO instance definitions (`instances:` key) |
| `workload.yaml` | Application workload values (`workload:` key) |

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
helm template argocd/charts/instances/
helm template argocd/charts/resource-groups/

# Validate with values
helm template argocd/charts/application-sets/ -f argocd/addons/csoc/addons.yaml
helm template argocd/charts/instances/ -f argocd/cluster-fleet/spoke1/infrastructure.yaml
```
