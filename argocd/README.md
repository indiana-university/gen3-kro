# ArgoCD GitOps Configuration

## Overview

This directory contains the declarative GitOps configuration for a multi-cluster EKS platform. ArgoCD on the CSOC cluster reconciles this directory tree to provision spoke infrastructure and deploy workloads via KRO + ACK controllers.

## Directory Structure

```
argocd/
├── addons/                         # Addon value files (merged via multi-source Helm)
│   └── addons.yaml                 #   Single file: EKS CSOC addons + Kind local addons
├── csoc-eks/                       # EKS CSOC cluster artifacts
│   ├── bootstrap/                  #   Entry-point ApplicationSets (Terraform bootstrap reads this)
│   │   ├── csoc-addons.yaml        #     CSOC addon ApplicationSet (wave -20)
│   │   ├── ack-multi-acct.yaml     #     ACK CARM multi-account ApplicationSet (wave 5)
│   │   └── fleet-instances.yaml    #     KRO instance Helm chart ApplicationSet (wave 30)
│   └── charts/                     #   Helm charts consumed by ApplicationSets
│       ├── addons/                 #     ACK multi-account Helm chart
│       ├── agrocd-application-sets/ #    Meta-chart: generates per-addon ApplicationSets
│       ├── aws-rgds-v1/            #     Chart A: KRO RGD delivery (plain YAML, no Helm directives)
│       │   └── templates/          #       RGD YAML files (modular + capability tests)
│   ├── aws-rgd-instances/      #     Chart B: per-spoke ConfigMap + KRO instance CRs
│       │   └── templates/          #       _helpers.tpl, configmap.yaml, instances.yaml
│       └── test-kro-graphs/        #     KRO capability test RGDs
├── csoc-local-kind/                # Local Kind CSOC cluster artifacts
│   ├── charts/                     #   Same chart structure as csoc-eks/charts/
│   ├── fleet/                      #   Local Kind spoke values (mirrors spoke-fleet/)
│   └── test/                       #   Local Kind test instances
└── spokes/                     # Per-spoke Helm values files
    └── spoke1/
        ├── infrastucture-values.yaml   # Layer 1: ConfigMap data + instance toggles
        ├── cluster-resources/          # Layer 2: cluster add-on values
        └── <hostname>/                 # Layer 3: gen3-helm values
```

## Reconciliation Chain

ArgoCD reconciliation follows this chain, enforced by sync waves:

```
Terraform creates:
  └── Bootstrap ApplicationSet (helm_release)
        └── Reads argocd/csoc-eks/bootstrap/ directory
              ├── csoc-addons.yaml → csoc-addons AppSet (wave -20)
              │                      └── KRO (wave -30)
              │                      └── ACK controllers (wave 1)
              │                      └── KRO RGDs via aws-rgds-v1 chart (wave 10)
              │                      └── External Secrets (wave 15)
              │
              ├── ack-multi-acct.yaml → ack-multi-acct AppSet (wave 5)
              │                         └── CARM namespaces + IAMRoleSelectors
              │
              └── fleet-instances.yaml → fleet-instances AppSet (wave 30)
                                         └── gen3-kro-infrastrructure chart per spoke
                                             (ConfigMap wave 14 + instances waves 15–30)
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
2. `csoc/controller-values/values.yaml`
3. `csoc/controller-values/<cluster_type>-overrides/addons.yaml`
4. `spokes/<cluster>/addons/<chart>/values.yaml` **(highest — wins)**

The merge uses multi-source Helm with ref-based value files:
```yaml
sources:
  - ref: values
    repoURL: '{{.metadata.annotations.addons_repo_url}}'
    targetRevision: '{{.metadata.annotations.addons_repo_revision}}'
  - repoURL: '{{.metadata.annotations.addons_repo_url}}'
    path: '{{.metadata.annotations.addons_repo_basepath}}csoc/helm/agrocd-application-sets'
    helm:
      ignoreMissingValueFiles: true
      valueFiles:
        - $values/{{.metadata.annotations.addons_repo_basepath}}csoc/controller-values/values.yaml
        - $values/{{.metadata.annotations.addons_repo_basepath}}csoc/controller-values/{{index .metadata.labels "cluster_type" | default "eks"}}-overrides/addons.yaml
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

### aws-rgds-v1 (Chart A — RGD delivery)

Plain KRO `ResourceGraphDefinition` YAML files. Files follow naming: `<tier>-<provider><name>-rg.yaml`
(e.g., `00-network1-rg.yaml`). Also contains KRO capability test RGDs (`krotest*-rg.yaml`).

**No Helm directives inside RGD files.** The chart is a versioned packaging wrapper only.
`values.yaml` is intentionally empty.

### aws-rgd-instances (Chart B — instance delivery)

Helm-templated chart that generates per-spoke KRO instance CRs and the `infrastructure-values`
ConfigMap. Spoke-specific configuration comes from `spokes/<spoke>/infrastucture-values.yaml`
via ArgoCD multi-source. The `gen3kro.instance` helper macro enforces consistent metadata.

### agrocd-application-sets (Meta-chart)

Generates one ApplicationSet per enabled addon key in values:

```yaml
addon-name:
  enabled: true                    # Required
  syncWave: "1"                    # Required — install order
  chartUrl: "oci://registry..."    # Helm chart URL
  chartName: "chart-name"          # Chart name
  chartVersion: "1.0.0"            # Pinned version
  namespace: "addon-ns"            # Target namespace
  type: manifest                   # Optional — "manifest" for plain YAML dirs
  repoPath: "csoc/helm/aws-rgds-v1"  # Required if type=manifest
  selectors:                       # Optional — extra label matchers
    ack_management_mode: self_managed
```

## CSOC Addons (`csoc/controller-values/`)

The base file contains shared addon definitions, including chart repositories,
versions, namespaces, and common selectors. EKS and Kind toggle enablement and
isolate cluster-specific settings in their override folders.

### EKS CSOC Addons

| Addon | Wave | Type | Purpose |
|-------|------|------|---------|
| `self-managed-kro` | -30 | Helm (OCI) | KRO controller — must be first |
| `ack-*-controller` (18x) | 1 | Helm (OCI) | ACK: acm, cloudtrail, cloudwatchlogs, ec2, efs, eks, elasticache, iam, kms, lambda, opensearchservice, rds, route53, s3, secretsmanager, sns, sqs, wafv2 |
| `kro-csoc-rgs` | 10 | manifest | KRO ResourceGraphDefinitions |
| `external-secrets` | 15 | Helm | External Secrets Operator |

### Kind Local Addons

| Addon | Wave | Type | Purpose |
|-------|------|------|---------|
| `self-managed-kro` | -30 | Helm | KRO controller |
| `kro-csoc-rgs` | 10 | manifest | KRO ResourceGraphDefinitions |
| `ack-*` (13x) | 1 | Helm (OCI) | ACK: acm, ec2, eks, elasticache, iam, kms, opensearchservice, rds, route53, s3, secretsmanager, sqs, wafv2 |

## Spoke Fleet (`spokes/<spoke>/`)

Each subdirectory is a spoke cluster identified by spoke alias. Used by the `fleet-instances`
ApplicationSet as Helm values override for `aws-rgd-instances` Chart B.

| Path | Purpose |
|------|---------|
| `infrastucture-values.yaml` | ConfigMap data + instance enabled/version/spec overrides (wave 14–30) |
| `cluster-resources/` | Cluster add-on values (for gen3-build chart) |
| `<hostname>/` | gen3-helm values (gen3-helm operator preferences) |

The `csoc-local-kind/fleet/` directory mirrors this structure for local Kind clusters.

## Conventions

- All ApplicationSets use `goTemplate: true` (Go template syntax required)
- Bootstrap directory files must be valid Kubernetes manifests (not Helm values)
- Addon keys use kebab-case: `external-secrets`, `self-managed-kro`
- Cluster fleet directories must match spoke aliases from `shared.auto.tfvars.json` (`spoke_account_ids` keys)
- Empty YAML files must contain `{}` (not blank)
- `ignoreMissingValueFiles: true` — optional overlays don't cause errors

## Validation

```bash
# Validate Chart B renders correctly for a spoke
helm template aws-rgd-instances argocd/csoc/helm/aws-rgd-instances \
  -f argocd/spokes/spoke1/infrastucture-values.yaml \
  | grep "^kind:"

# Lint Chart A
helm lint argocd/csoc/helm/aws-rgds-v1/

# Lint Chart B
helm lint argocd/csoc/helm/aws-rgd-instances/ \
  -f argocd/spokes/spoke1/infrastucture-values.yaml
```
