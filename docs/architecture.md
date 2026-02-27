# Architecture

Detailed architecture documentation for the EKS Cluster Management Platform.

> **Diagrams:** All diagrams are stored as `.drawio` files in [`docs/diagrams/`](diagrams/). Click any diagram link to open it in VS Code (requires the [Draw.io Integration](https://marketplace.visualstudio.com/items?itemName=hediet.vscode-drawio) extension). Inline rendering in markdown preview is available with [vscode-drawio-plugin-markdown](https://marketplace.visualstudio.com/items?itemName=dzylikecode.vscode-drawio-plugin-markdown).

## Table of Contents

- [Platform Overview](#platform-overview)
- [Two-Phase Deployment Model](#two-phase-deployment-model)
- [Terraform Module Hierarchy](#terraform-module-hierarchy)
- [ArgoCD Reconciliation Chain](#argocd-reconciliation-chain)
- [Cross-Account Trust Model](#cross-account-trust-model)
- [Data Flow](#data-flow)
- [Sync Wave Ordering](#sync-wave-ordering)

---

## Platform Overview

**Diagram:** [docs/diagrams/platform-overview.drawio](diagrams/platform-overview.drawio)

The platform uses a CSOC (Cybersecurity Operations Center) EKS cluster as the central control plane. This cluster runs ArgoCD, KRO, and ACK controllers that provision and manage infrastructure across multiple AWS spoke accounts.

```
CSOC Account
└── EKS Cluster ({csoc_alias}-csoc-cluster)
    ├── ArgoCD               — GitOps controller (git → cluster)
    ├── KRO                  — Composes ACK resources into single custom resources
    ├── ACK Controllers x17  — Provisions AWS resources via K8s CRDs
    ├── ResourceGraphDefs    — KRO schema templates (VPC + EKS + RDS bundles)
    └── External Secrets     — Syncs Secrets Manager → K8s secrets

Cross-account (STS AssumeRole)
├── Spoke Account 1  → VPC, EKS, RDS, S3 (managed by ACK)
└── Spoke Account 2  → VPC, EKS, RDS, S3 (managed by ACK)
```

### Component Roles

| Component | Purpose |
|-----------|---------|
| **ArgoCD** | GitOps controller — reconciles git repo state to cluster |
| **KRO** | Kubernetes Resource Orchestrator — composes multiple ACK resources into a single CRD instance |
| **ACK** | AWS Controllers for Kubernetes — manages AWS resources as K8s custom resources |
| **ResourceGraphDefinitions** | KRO CRD schemas defining infrastructure templates (e.g., VPC + EKS + RDS) |
| **External Secrets** | Syncs credentials from AWS Secrets Manager into K8s secrets |

---

## Two-Phase Deployment Model

**Diagram:** [docs/diagrams/deployment-phases.drawio](diagrams/deployment-phases.drawio)

Deployment is split across two execution contexts to solve the circular dependency between spoke IAM roles and the CSOC EKS cluster.

```
Phase 1 — HOST (Terragrunt)
  mfa-session.sh → ~/.aws/credentials [csoc]
  terragrunt stack run apply
    └── aws_spoke_spoke1, aws_spoke_spoke2
          → Create ACK workload roles with account-root trust

Phase 2 — CONTAINER / WSL (Terraform)
  bash scripts/install.sh apply
    → config/shared.auto.tfvars.json (single source of truth)
    → module.aws_csoc
        ├── VPC + EKS cluster
        ├── OIDC Provider
        ├── ACK source IAM role (OIDC-trusted)
        └── ArgoCD Helm install
    → module.argocd_bootstrap
        ├── ArgoCD cluster secret (labels + annotations)
        ├── Git repo credentials secret
        ├── Bootstrap ApplicationSet (Helm release)
        └── connect-csoc.sh (local_file output)

Phase 3 — ArgoCD (Automatic GitOps)
  Bootstrap AppSet reads argocd/bootstrap/
    → csoc-addons AppSet (wave -20)
    → spoke-addons AppSet (wave 20)
    → fleet AppSet (wave 30)
  Sync waves enforce: KRO → ACK → RGDs → ESO → Spoke → Instances
```

### Why Two Phases?

Spoke workload roles must trust the CSOC ACK source role, but that role requires an EKS OIDC provider that doesn't exist until the cluster is created. The solution:

1. **Phase 1** creates spoke roles with **account-root trust** (`arn:aws:iam::<CSOC>:root`) — the account principal always exists
2. **Phase 2** creates the EKS cluster and ACK source role
3. The ACK source role satisfies the `ArnLike` condition on spoke roles at assume-time (evaluated dynamically at each `sts:AssumeRole` call)

---

## Terraform Module Hierarchy

**Diagram:** [docs/diagrams/module-hierarchy.drawio](diagrams/module-hierarchy.drawio)

```
terraform/env/aws/csoc-cluster/      ← Single entry point (root module)
└── module "csoc_cluster"
    └── terraform/catalog/modules/csoc-cluster/   ← Composite wrapper
        ├── module "aws_csoc"
        │   └── terraform/catalog/modules/aws-csoc/
        │       ├── vpc.tf                         EKS-optimized VPC
        │       ├── eks.tf                         EKS cluster + OIDC
        │       ├── ack-iam.tf                     ACK source IAM role
        │       ├── argocd.tf                      ArgoCD Helm release
        │       └── external-secrets.tf            Pod identity for ESO
        │
        └── module "argocd_bootstrap"              (depends on aws_csoc outputs)
            └── terraform/catalog/modules/argocd-bootstrap/
                ├── cluster-secret.tf              ArgoCD cluster secret
                ├── git-secret.tf                  Git repo credentials
                ├── bootstrap.tf                   Bootstrap ApplicationSet
                └── outputs.tf                     connect-csoc.sh script

terraform/catalog/units/aws-spoke/   ← Terragrunt unit wrappers (HOST only)
terragrunt/live/aws/csoc-cluster/    ← Spoke stack (aws_spoke_spoke1, aws_spoke_spoke2)
```

### Module Responsibilities

| Module | Runs In | Creates |
|--------|---------|---------|
| `csoc-cluster` | Container | Thin composite wrapper — calls `aws-csoc` + `argocd-bootstrap` |
| `aws-csoc` | Container | VPC, EKS, OIDC, ACK source IAM role, ArgoCD Helm, External Secrets pod identity |
| `argocd-bootstrap` | Container | ArgoCD cluster secret, git repo secret, bootstrap ApplicationSet Helm release, `connect-csoc.sh` |
| `aws-spoke` | Host | Per-spoke ACK workload IAM roles with account-root + ArnLike trust |

### Dependency Chain

```
aws-csoc outputs → argocd-bootstrap inputs
  cluster_endpoint          → kubernetes provider
  cluster_certificate_authority_data → kubernetes provider
  argocd_namespace          → helm_release.bootstrap namespace
  ack_role_arn              → cluster secret annotation
```

Terraform resolves this implicitly via data references — `argocd-bootstrap` cannot plan/apply until `aws-csoc` has real output values.

---

## ArgoCD Reconciliation Chain

**Diagram:** [docs/diagrams/argocd-reconciliation.drawio](diagrams/argocd-reconciliation.drawio)

After Terraform creates the bootstrap ApplicationSet, ArgoCD takes over and reconciles the entire platform configuration from git.

```
helm_release.bootstrap
└── Bootstrap ApplicationSet (reads argocd/bootstrap/)
    └── bootstrap Application
        ├── csoc-addons.yaml
        │   └── csoc-addons ApplicationSet (fleet_member: control-plane)
        │       ├── self-managed-kro Application        (wave -30)
        │       ├── ack-ec2/eks/iam/rds/... x17         (wave 1)
        │       ├── kro-eks-rgs Application             (wave 10)
        │       └── external-secrets Application        (wave 15)
        │
        ├── spoke-addons.yaml
        │   └── spoke-addons ApplicationSet (fleet_member: spoke)
        │       └── external-secrets-per-spoke           (wave 20)
        │
        ├── cross-acct.yaml
        │   └── ack-multi-acct ApplicationSet (wave 5)
        │       └── ACK CARM namespaces + IAMRoleSelectors
        │
        └── cluster-fleet.yaml
            ├── fleet ApplicationSet (fleet_member: fleet-spoke-infra)
            │   └── KRO Instances (VPC, EKS, RDS...)    (wave 30)
            └── fleet-workloads ApplicationSet (fleet_member: spoke)
                └── Gen3 workloads on spoke clusters     (wave 40)
```

### Bootstrap Directory → ApplicationSet Mapping

| File in `argocd/bootstrap/` | ApplicationSet(s) Created | Sync Wave |
|------------------------------|--------------------------|-----------|
| `csoc-addons.yaml` | `csoc-addons` | -20 |
| `cross-acct.yaml` | `ack-multi-acct` | 5 |
| `spoke-addons.yaml` | `spoke-addons` | 20 |
| `cluster-fleet.yaml` | `fleet`, `fleet-workloads` | 30, 40 |

### Values Merge Priority (last wins, maps deep-merged)

```
1. Helm chart defaults         (argocd/charts/<chart>/values.yaml)
2. Env or CSOC addons          (argocd/addons/csoc/addons.yaml)
3. Cluster-fleet overrides     (argocd/cluster-fleet/<cluster>/addons.yaml)  ← WINS
```

---

## Cross-Account Trust Model

**Diagram:** [docs/diagrams/cross-account-trust.drawio](diagrams/cross-account-trust.drawio)

```
CSOC Account
  EKS OIDC Provider
    ─① IRSA trust─→  ACK Source Role
                      ({csoc_alias}-csoc-role)
                         ↑
  ACK Controller Pods ──② assume via OIDC

                      ─③ sts:AssumeRole──→  Spoke1 Workload Role
                         ArnLike=*-csoc-role       → manages AWS resources

                      ─③ sts:AssumeRole──→  Spoke2 Workload Role
                                             → manages AWS resources
```

### Trust Policy Pattern (Spoke Side)

```json
{
  "Principal": { "AWS": "arn:aws:iam::<CSOC_ACCOUNT>:root" },
  "Condition": {
    "ArnLike": { "aws:PrincipalArn": "arn:aws:iam::<CSOC_ACCOUNT>:role/*-csoc-role" }
  }
}
```

- **Account-root principal** — always valid, even before the ACK source role ARN exists
- **ArnLike condition** — restricts to roles matching the `*-csoc-role` naming pattern (evaluated at assume-time)
- No ExternalId — ACK does not pass it during `sts:AssumeRole`

### IAM Policy Files

```
iam/
├── _default/ack/inline-policy.json    # Fallback — used for any spoke without its own policy
└── spoke2/ack/inline-policy.json      # Spoke2-specific permissions
```

The `aws-spoke` module reads these files at plan time via `file()`. Spokes without a custom `iam/<alias>/ack/` directory automatically fall back to `_default`.

---

## Data Flow

### shared.auto.tfvars.json → Running Infrastructure

```
config/shared.auto.tfvars.json (gitignored, single source of truth)
  └─► scripts/install.sh
        ├── jq parsing (extracts backend config)
        └── symlinks into terraform workdir
              └─► terraform/env/aws/csoc-cluster/ (root module)
                    ├── module.aws_csoc
                    │     ├── spoke_account_ids → ACK source role trust
                    │     ├── csoc_alias, region → EKS naming + config
                    │     └── outputs ──────────────────────────────┐
                    └── module.argocd_bootstrap ◄────────────────────┘
                          ├── kubernetes_secret (cluster)
                          │     ├── labels    →  ApplicationSet cluster generator
                          │     └── annotations → Go template variables
                          ├── kubernetes_secret (git repo)
                          └── helm_release (bootstrap ApplicationSet)
                                └─► ArgoCD reconciles git → cluster state
```

### Key Data Handoffs

| From | To | Data | Mechanism |
|------|----|------|-----------|
| `shared.auto.tfvars.json` | Terraform | All module variables | Auto-loaded (symlinked into workdir by install.sh) |
| `shared.auto.tfvars.json` | Terraform | State bucket, key, region | Extracted by install.sh → `-backend-config` at init |
| `aws-csoc` | `argocd-bootstrap` | Endpoint, CA, argocd namespace, ACK role ARN | Terraform module output references |
| Terraform | ArgoCD | Labels, annotations, spoke account IDs | Kubernetes cluster secret |
| ArgoCD | ApplicationSets | Cluster metadata | Cluster generator `matchLabels` + Go templates |
| ApplicationSets | Helm charts | Addon config, infra specs | Multi-source `valueFiles` merge (3 layers) |

---

## Sync Wave Ordering

Sync waves enforce a deterministic deployment order. Resources in lower waves must reach Healthy status before higher waves are processed.

| Wave | Resource | Depends On | Why This Order |
|------|----------|------------|----------------|
| -30 | KRO controller | — | Must be present before any KRO CRDs are applied |
| -20 | CSOC addons ApplicationSet | KRO running | AppSet itself is a CRD-backed resource |
| 1 | ACK controllers (17 services) | KRO | CRD registration must precede ACK instance creation |
| 5 | ACK multi-account (CARM) | ACK controllers | CARM namespaces and IAMRoleSelectors require ACK CRDs |
| 10 | KRO ResourceGraphDefinitions | KRO, ACK | RGDs reference ACK CRDs; CRDs must exist |
| 15 | External Secrets Operator | — | Independent; can start anytime after cluster exists |
| 20 | Spoke addons ApplicationSet | ACK, RGDs | Spoke ESO needs the RGD-defined secret stores |
| 30 | Fleet KRO instances | ACK, RGDs, spoke addons | KRO instances expand into ACK resources using RGDs |
| 40 | Fleet workloads | KRO instances healthy | Workloads gate on KRO-created argoCDClusterSecret |
| 50 | Individual Gen3 workloads | Fleet workloads | Per-service Applications on spoke clusters |

---

## Directory Reference

```
eks-cluster-mgmt/
├── README.md                            # Project overview + quick start
├── AGENTS.md                            # AI agent deployment instructions
├── Dockerfile                           # Dev container base image
│
├── argocd/
│   ├── README.md                        #   ArgoCD layer documentation
│   ├── bootstrap/
│   │   ├── csoc-addons.yaml             #   CSOC addon ApplicationSet (wave -20)
│   │   ├── spoke-addons.yaml            #   Spoke addon ApplicationSet (wave 20)
│   │   ├── cross-acct.yaml              #   ACK CARM multi-account (wave 5)
│   │   └── cluster-fleet.yaml           #   Fleet infra + workloads ApplicationSets (wave 30, 40)
│   ├── addons/
│   │   ├── csoc/addons.yaml             #   CSOC addon values (KRO, ACK, ESO)
│   │   └── environments/{dev,prod}/     #   Environment-specific addon values
│   ├── charts/
│   │   ├── application-sets/            #   Meta-chart: generates child ApplicationSets
│   │   ├── instances/                   #   KRO instance renderer chart
│   │   ├── multi-acct/                  #   ACK CARM namespace + IAMRoleSelector chart
│   │   ├── resource-groups/             #   KRO RGD manifests chart
│   │   └── workloads/                   #   Gen3 workload Helm chart
│   └── cluster-fleet/
│       └── {csoc,spoke1,spoke2}/        #   Per-cluster addon + infra overrides
│           ├── addons.yaml
│           ├── infrastructure.yaml
│           └── workload.yaml
│
├── terraform/
│   ├── env/aws/csoc-cluster/             # Root module (single entry point)
│   │   ├── main.tf                      #   Module invocation
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── provider.tf
│   │   └── backend.tf
│   └── catalog/
│       ├── modules/
│       │   ├── csoc-cluster/            #   Composite (aws-csoc + argocd-bootstrap)
│       │   ├── aws-csoc/                #   EKS, VPC, ACK IAM, ArgoCD Helm
│       │   ├── argocd-bootstrap/        #   Cluster secret, git secret, bootstrap AppSet
│       │   ├── aws-spoke/               #   Spoke workload IAM roles (HOST only)
│       │   └── developer-identity/      #   Developer IAM resources
│       └── units/                       #   Terragrunt unit wrappers
│
├── terragrunt/live/aws/iam-setup/    # Spoke IAM Terragrunt stack
│
├── iam/
│   ├── _default/ack/inline-policy.json  # Default ACK permissions (fallback for all spokes)
│   ├── _default/argocd/inline-policy.json # ArgoCD spoke role permissions (reference)
│   └── spoke2/ack/inline-policy.json    # Spoke2-specific permissions (override when needed)
│
├── scripts/
│   ├── install.sh                       #   Terraform orchestrator (init/plan/apply)
│   ├── destroy.sh                       #   Full teardown
│   ├── mfa-session.sh                   #   Host MFA credential setup
│   └── container-init.sh               #   Container environment setup
│
├── docs/
│   ├── architecture.md                  #   This file
│   ├── deployment-guide.md              #   Step-by-step deployment procedures
│   ├── security.md                      #   Security model and IAM details
│   └── diagrams/                        #   Draw.io diagram source files
│       ├── platform-overview.drawio
│       ├── deployment-phases.drawio
│       ├── argocd-reconciliation.drawio
│       ├── cross-account-trust.drawio
│       └── module-hierarchy.drawio
│
└── outputs/                             # Generated artifacts (gitignored)
    ├── logs/                            #   Terraform plan/apply logs
    ├── connect-csoc.sh                  #   Cluster connection script
    └── argocd-password.txt             #   ArgoCD admin password
```
