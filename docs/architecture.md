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
- [Local CSOC (Kind)](#local-csoc-kind)

---

## Platform Overview

**Diagram:** [docs/diagrams/platform-overview.drawio](diagrams/platform-overview.drawio)

The platform uses a CSOC (Cybersecurity Operations Center) EKS cluster as the central control plane. This cluster runs ArgoCD, KRO, and ACK controllers that provision and manage infrastructure across multiple AWS spoke accounts.

```
CSOC Account
â””â”€â”€ EKS Cluster ({csoc_alias}-csoc-cluster)
    â”œâ”€â”€ ArgoCD               â€” GitOps controller (git â†’ cluster)
    â”œâ”€â”€ KRO                  â€” Composes ACK resources into single custom resources
    â”œâ”€â”€ ACK Controllers x17  â€” Provisions AWS resources via K8s CRDs
    â”œâ”€â”€ ResourceGraphDefs    â€” KRO schema templates (VPC + EKS + RDS bundles)
    â””â”€â”€ External Secrets     â€” Syncs Secrets Manager â†’ K8s secrets

Cross-account (STS AssumeRole)
â”œâ”€â”€ Spoke Account 1  â†’ VPC, EKS, RDS, S3 (managed by ACK)
â””â”€â”€ Spoke Account 2  â†’ VPC, EKS, RDS, S3 (managed by ACK)
```

### Component Roles

| Component | Purpose |
|-----------|---------|
| **ArgoCD** | GitOps controller â€” reconciles git repo state to cluster |
| **KRO** | Kubernetes Resource Orchestrator â€” composes multiple ACK resources into a single CRD instance |
| **ACK** | AWS Controllers for Kubernetes â€” manages AWS resources as K8s custom resources |
| **ResourceGraphDefinitions** | KRO CRD schemas defining infrastructure templates (e.g., VPC + EKS + RDS) |
| **External Secrets** | Syncs credentials from AWS Secrets Manager into K8s secrets |

---

## Two-Phase Deployment Model

**Diagram:** [docs/diagrams/deployment-phases.drawio](diagrams/deployment-phases.drawio)

Deployment is split across two execution contexts to solve the circular dependency between spoke IAM roles and the CSOC EKS cluster.

```
Phase 1 â€” HOST (Terragrunt)
  mfa-session.sh â†’ ~/.aws/credentials [csoc]
  terragrunt stack run apply
    â””â”€â”€ aws_spoke_spoke1, aws_spoke_spoke2
          â†’ Create ACK workload roles with account-root trust

Phase 2 â€” CONTAINER / WSL (Terraform)
  bash scripts/install.sh apply
    â†’ config/shared.auto.tfvars.json (single source of truth)
    â†’ module.aws_csoc
        â”œâ”€â”€ VPC + EKS cluster
        â”œâ”€â”€ OIDC Provider
        â”œâ”€â”€ ACK source IAM role (OIDC-trusted)
        â””â”€â”€ ArgoCD Helm install
    â†’ module.argocd_bootstrap
        â”œâ”€â”€ ArgoCD cluster secret (labels + annotations)
        â”œâ”€â”€ Git repo credentials secret
        â”œâ”€â”€ Bootstrap ApplicationSet (Helm release)
        â””â”€â”€ connect-csoc.sh (local_file output)

Phase 3 â€” ArgoCD (Automatic GitOps)
  Bootstrap AppSet reads argocd/bootstrap/
    â†’ csoc-addons AppSet (wave -20)
    â†’ ack-multi-acct AppSet (wave 5)
    â†’ fleet-instances AppSet (wave 30)  [picks up argocd/fleet/{spoke}/**]
  Sync waves enforce: KRO â†’ ACK â†’ RGDs â†’ Infra Instances â†’ ClusterResources â†’ Gen3
```

### Why Two Phases?

Spoke workload roles must trust the CSOC ACK source role, but that role requires an EKS OIDC provider that doesn't exist until the cluster is created. The solution:

1. **Phase 1** creates spoke roles with **account-root trust** (`arn:aws:iam::<CSOC>:root`) â€” the account principal always exists
2. **Phase 2** creates the EKS cluster and ACK source role
3. The ACK source role satisfies the `ArnLike` condition on spoke roles at assume-time (evaluated dynamically at each `sts:AssumeRole` call)

---

## Terraform Module Hierarchy

**Diagram:** [docs/diagrams/module-hierarchy.drawio](diagrams/module-hierarchy.drawio)

```
terraform/env/aws/csoc-cluster/      â† Single entry point (root module)
â””â”€â”€ module "csoc_cluster"
    â””â”€â”€ terraform/catalog/modules/csoc-cluster/   â† Composite wrapper
        â”œâ”€â”€ module "aws_csoc"
        â”‚   â””â”€â”€ terraform/catalog/modules/aws-csoc/
        â”‚       â”œâ”€â”€ vpc.tf                         EKS-optimized VPC
        â”‚       â”œâ”€â”€ eks.tf                         EKS cluster + OIDC
        â”‚       â”œâ”€â”€ ack-iam.tf                     ACK source IAM role
        â”‚       â”œâ”€â”€ argocd.tf                      ArgoCD Helm release
        â”‚       â””â”€â”€ external-secrets.tf            Pod identity for ESO
        â”‚
        â””â”€â”€ module "argocd_bootstrap"              (depends on aws_csoc outputs)
            â””â”€â”€ terraform/catalog/modules/argocd-bootstrap/
                â”œâ”€â”€ cluster-secret.tf              ArgoCD cluster secret
                â”œâ”€â”€ git-secret.tf                  Git repo credentials
                â”œâ”€â”€ bootstrap.tf                   Bootstrap ApplicationSet
                â””â”€â”€ outputs.tf                     connect-csoc.sh script

terraform/catalog/units/aws-spoke/   â† Terragrunt unit wrappers (HOST only)
terragrunt/live/aws/csoc-cluster/    â† Spoke stack (aws_spoke_spoke1, aws_spoke_spoke2)
```

### Module Responsibilities

| Module | Runs In | Creates |
|--------|---------|---------|
| `csoc-cluster` | Container | Thin composite wrapper â€” calls `aws-csoc` + `argocd-bootstrap` |
| `aws-csoc` | Container | VPC, EKS, OIDC, ACK source IAM role, ArgoCD Helm, External Secrets pod identity |
| `argocd-bootstrap` | Container | ArgoCD cluster secret, git repo secret, bootstrap ApplicationSet Helm release, `connect-csoc.sh` |
| `aws-spoke` | Host | Per-spoke ACK workload IAM roles with account-root + ArnLike trust |

### Dependency Chain

```
aws-csoc outputs â†’ argocd-bootstrap inputs
  cluster_endpoint          â†’ kubernetes provider
  cluster_certificate_authority_data â†’ kubernetes provider
  argocd_namespace          â†’ helm_release.bootstrap namespace
  ack_role_arn              â†’ cluster secret annotation
```

Terraform resolves this implicitly via data references â€” `argocd-bootstrap` cannot plan/apply until `aws-csoc` has real output values.

---

## ArgoCD Reconciliation Chain

**Diagram:** [docs/diagrams/argocd-reconciliation.drawio](diagrams/argocd-reconciliation.drawio)

After Terraform creates the bootstrap ApplicationSet, ArgoCD takes over and reconciles the entire platform configuration from git.

```
helm_release.bootstrap
â””â”€â”€ Bootstrap ApplicationSet (reads argocd/bootstrap/)
    â””â”€â”€ bootstrap Application
        â”œâ”€â”€ csoc-addons.yaml
        â”‚   â””â”€â”€ csoc-addons ApplicationSet (fleet_member: control-plane)
        â”‚       â”œâ”€â”€ self-managed-kro Application        (wave -30)
        â”‚       â”œâ”€â”€ ack-ec2/eks/iam/rds/... x17         (wave 1)
        â”‚       â”œâ”€â”€ kro-eks-rgs Application             (wave 10)
        â”‚       â””â”€â”€ external-secrets Application        (wave 15)
        â”‚
        â”œâ”€â”€ ack-multi-acct.yaml
        â”‚   â””â”€â”€ ack-multi-acct ApplicationSet (wave 5)
        â”‚       â””â”€â”€ ACK CARM namespaces + IAMRoleSelectors
        â”‚
        â””â”€â”€ fleet-instances.yaml
            â””â”€â”€ fleet-instances ApplicationSet (recurse: argocd/fleet/{spoke}/**)
                â”œâ”€â”€ infra KRO instances                  (waves 15-25)
                â”œâ”€â”€ AwsGen3ClusterResources2 instance     (wave 27)
                â””â”€â”€ AwsGen3Helm1 instance                (wave 30)
                    ClusterResources1 creates ArgoCD Application â†’ spoke cluster
                    Helm1 creates ArgoCD Application â†’ spoke cluster
```

### Bootstrap Directory â†’ ApplicationSet Mapping

| File in `argocd/bootstrap/` | ApplicationSet(s) Created | Sync Wave |
|------------------------------|--------------------------|----------|
| `csoc-addons.yaml` | `csoc-addons` | -20 |
| `ack-multi-acct.yaml` | `ack-multi-acct` | 5 |
| `fleet-instances.yaml` | `fleet-instances` | 30 |

### Values Merge Priority (last wins, maps deep-merged)

```
1. Helm chart defaults         (argocd/charts/<chart>/values.yaml)
2. CSOC addons                 (argocd/addons/csoc/addons.yaml)
3. Fleet instance overrides    (argocd/fleet/<spoke>/)  â† WINS
```

---

## Cross-Account Trust Model

**Diagram:** [docs/diagrams/cross-account-trust.drawio](diagrams/cross-account-trust.drawio)

```
CSOC Account
  EKS OIDC Provider
    â”€â‘  IRSA trustâ”€â†’  ACK Source Role
                      ({csoc_alias}-csoc-role)
                         â†‘
  ACK Controller Pods â”€â”€â‘¡ assume via OIDC

                      â”€â‘¢ sts:AssumeRoleâ”€â”€â†’  Spoke1 Workload Role
                         ArnLike=*-csoc-role       â†’ manages AWS resources

                      â”€â‘¢ sts:AssumeRoleâ”€â”€â†’  Spoke2 Workload Role
                                             â†’ manages AWS resources
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

- **Account-root principal** â€” always valid, even before the ACK source role ARN exists
- **ArnLike condition** â€” restricts to roles matching the `*-csoc-role` naming pattern (evaluated at assume-time)
- No ExternalId â€” ACK does not pass it during `sts:AssumeRole`

### IAM Policy Files

```
iam/
â”œâ”€â”€ _default/ack/inline-policy.json    # Fallback â€” used for any spoke without its own policy
â””â”€â”€ spoke2/ack/inline-policy.json      # Spoke2-specific permissions
```

The `aws-spoke` module reads these files at plan time via `file()`. Spokes without a custom `iam/<alias>/ack/` directory automatically fall back to `_default`.

---

## Data Flow

### shared.auto.tfvars.json â†’ Running Infrastructure

```
config/shared.auto.tfvars.json (gitignored, single source of truth)
  â””â”€â–º scripts/install.sh
        â”œâ”€â”€ jq parsing (extracts backend config)
        â””â”€â”€ symlinks into terraform workdir
              â””â”€â–º terraform/env/aws/csoc-cluster/ (root module)
                    â”œâ”€â”€ module.aws_csoc
                    â”‚     â”œâ”€â”€ spoke_account_ids â†’ ACK source role trust
                    â”‚     â”œâ”€â”€ csoc_alias, region â†’ EKS naming + config
                    â”‚     â””â”€â”€ outputs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
                    â””â”€â”€ module.argocd_bootstrap â—„â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                          â”œâ”€â”€ kubernetes_secret (cluster)
                          â”‚     â”œâ”€â”€ labels    â†’  ApplicationSet cluster generator
                          â”‚     â””â”€â”€ annotations â†’ Go template variables
                          â”œâ”€â”€ kubernetes_secret (git repo)
                          â””â”€â”€ helm_release (bootstrap ApplicationSet)
                                â””â”€â–º ArgoCD reconciles git â†’ cluster state
```

### Key Data Handoffs

| From | To | Data | Mechanism |
|------|----|------|-----------|
| `shared.auto.tfvars.json` | Terraform | All module variables | Auto-loaded (symlinked into workdir by install.sh) |
| `shared.auto.tfvars.json` | Terraform | State bucket, key, region | Extracted by install.sh â†’ `-backend-config` at init |
| `aws-csoc` | `argocd-bootstrap` | Endpoint, CA, argocd namespace, ACK role ARN | Terraform module output references |
| Terraform | ArgoCD | Labels, annotations, spoke account IDs | Kubernetes cluster secret |
| ArgoCD | ApplicationSets | Cluster metadata | Cluster generator `matchLabels` + Go templates |
| ApplicationSets | Helm charts | Addon config, infra specs | Multi-source `valueFiles` merge (3 layers) |

---

## Sync Wave Ordering

Sync waves enforce a deterministic deployment order. Resources in lower waves must reach Healthy status before higher waves are processed.

| Wave | Resource | Depends On | Why This Order |
|------|----------|------------|----------------|
| -30 | KRO controller | â€” | Must be present before any KRO CRDs are applied |
| -20 | CSOC addons ApplicationSet | KRO running | AppSet itself is a CRD-backed resource |
| 1 | ACK controllers (17 services) | KRO | CRD registration must precede ACK instance creation |
| 5 | ACK multi-account (CARM) | ACK controllers | CARM namespaces and IAMRoleSelectors require ACK CRDs |
| 10 | KRO ResourceGraphDefinitions | KRO, ACK | RGDs reference ACK CRDs; CRDs must exist |
| 15 | External Secrets Operator | â€” | Independent; can start anytime after cluster exists |
| 30 | Fleet KRO instances | ACK, RGDs, ESO | KRO instances expand into ACK resources using RGDs |
| 40 | Fleet cluster-resources | KRO instances healthy | Cluster-level infra (external-secrets, cert-manager) on spoke |
| 50 | Fleet Gen3 apps | Fleet cluster-resources | Gen3 services on spoke clusters |

---

## Directory Reference

```
eks-cluster-mgmt/
â”œâ”€â”€ README.md                            # Project overview + quick start
â”œâ”€â”€ Dockerfile                           # Dev container base image
â”‚
â”œâ”€â”€ argocd/
â”‚   â”œâ”€â”€ README.md                        #   ArgoCD layer documentation
â”‚   â”œâ”€â”€ bootstrap/
â”‚   â”‚   â”œâ”€â”€ csoc-addons.yaml             #   CSOC addon ApplicationSet (wave -20)
â”‚   â”‚   â”œâ”€â”€ ack-multi-acct.yaml          #   ACK CARM multi-account (wave 5)
â”‚   â”‚   â””â”€â”€ fleet-instances.yaml         #   KRO instance CRs ApplicationSet (wave 30)
â”‚   â”œâ”€â”€ addons/
â”‚   â”‚   â””â”€â”€ addons.yaml                  #   CSOC + Kind addon values (KRO, ACK)
â”‚   â”œâ”€â”€ charts/
â”‚   â”‚   â”œâ”€â”€ application-sets/            #   Meta-chart: generates child ApplicationSets
â”‚   â”‚   â”œâ”€â”€ multi-acct/                  #   ACK CARM namespace + IAMRoleSelector chart
â”‚   â”‚   â””â”€â”€ resource-groups/             #   KRO RGD manifests chart
â”‚   â”œâ”€â”€ fleet/
â”‚   â”‚   â””â”€â”€ spoke1/                      #   Per-spoke KRO instance CRs
â”‚   â”‚       â”œâ”€â”€ infrastructure/          #   Infra tier instances + values ConfigMap
â”‚   â”‚       â”œâ”€â”€ cluster-level-resources/ #   ClusterResources2 instance + cluster-values
â”‚   â”‚       â””â”€â”€ {hostname}/              #   Helm1 instance + values
â”‚   â””â”€â”€ local-kind/
â”‚       â””â”€â”€ test/                        #   Local Kind KRO instances
â”‚           â”œâ”€â”€ infrastructure/          #   Real-AWS infra instances
â”‚           â”œâ”€â”€ tests/                   #   Capability test instances
â”‚           â”œâ”€â”€ cluster-resources/
â”‚           â””â”€â”€ applications/
â”‚
â”œâ”€â”€ terraform/
â”‚   â”œâ”€â”€ env/aws/csoc-cluster/             # Root module (single entry point)
â”‚   â”‚   â”œâ”€â”€ main.tf                      #   Module invocation
â”‚   â”‚   â”œâ”€â”€ variables.tf
â”‚   â”‚   â”œâ”€â”€ outputs.tf
â”‚   â”‚   â”œâ”€â”€ provider.tf
â”‚   â”‚   â””â”€â”€ backend.tf
â”‚   â””â”€â”€ catalog/
â”‚       â”œâ”€â”€ modules/
â”‚       â”‚   â”œâ”€â”€ csoc-cluster/            #   Composite (aws-csoc + argocd-bootstrap)
â”‚       â”‚   â”œâ”€â”€ aws-csoc/                #   EKS, VPC, ACK IAM, ArgoCD Helm
â”‚       â”‚   â”œâ”€â”€ argocd-bootstrap/        #   Cluster secret, git secret, bootstrap AppSet
â”‚       â”‚   â”œâ”€â”€ aws-spoke/               #   Spoke workload IAM roles (HOST only)
â”‚       â”‚   â””â”€â”€ developer-identity/      #   Developer IAM resources
â”‚       â””â”€â”€ units/                       #   Terragrunt unit wrappers
â”‚
â”œâ”€â”€ terragrunt/live/aws/iam-setup/    # Spoke IAM Terragrunt stack
â”‚
â”œâ”€â”€ iam/
â”‚   â”œâ”€â”€ _default/ack/inline-policy.json  # Default ACK permissions (fallback for all spokes)
â”‚   â”œâ”€â”€ _default/argocd/inline-policy.json # ArgoCD spoke role permissions (reference)
â”‚   â””â”€â”€ spoke2/ack/inline-policy.json    # Spoke2-specific permissions (override when needed)
â”‚
â”œâ”€â”€ scripts/
â”‚   â”œâ”€â”€ install.sh                       #   Terraform orchestrator (init/plan/apply)
â”‚   â”œâ”€â”€ destroy.sh                       #   Full teardown
â”‚   â”œâ”€â”€ mfa-session.sh                   #   Host MFA credential setup
â”‚   â””â”€â”€ container-init.sh               #   Container environment setup
â”‚
â”œâ”€â”€ docs/
â”‚   â”œâ”€â”€ architecture.md                  #   This file
â”‚   â”œâ”€â”€ deployment-guide.md              #   Step-by-step deployment procedures
â”‚   â”œâ”€â”€ security.md                      #   Security model and IAM details
â”‚   â””â”€â”€ diagrams/                        #   Draw.io diagram source files
â”‚       â”œâ”€â”€ platform-overview.drawio
â”‚       â”œâ”€â”€ deployment-phases.drawio
â”‚       â”œâ”€â”€ argocd-reconciliation.drawio
â”‚       â”œâ”€â”€ cross-account-trust.drawio
â”‚       â””â”€â”€ module-hierarchy.drawio
â”‚
â””â”€â”€ outputs/                             # Generated artifacts (gitignored)
    â”œâ”€â”€ logs/                            #   Terraform plan/apply logs
    â”œâ”€â”€ connect-csoc.sh                  #   Cluster connection script
    â””â”€â”€ argocd-password.txt             #   ArgoCD admin password
```

---

## Local CSOC (Kind)

The local CSOC is a **host-based** Kind cluster used for RGD authoring and
capability testing. It mirrors the EKS CSOC structure but runs entirely on the
developer's laptop without a DevContainer.

```
Developer's Laptop (host)
â””â”€â”€ Kind cluster (gen3-local)
    â”œâ”€â”€ ArgoCD               â€” GitOps controller (git â†’ cluster)
    â”œâ”€â”€ KRO                  â€” Composes ACK resources into single custom resources
    â”œâ”€â”€ ACK Controllers x9   â€” Provisions AWS resources via K8s CRDs
    â””â”€â”€ ResourceGraphDefs    â€” Same RGDs as EKS CSOC

via K8s Secret (ack-aws-credentials)
â””â”€â”€ Real AWS account  â†’ VPC, SGs, EKS, RDS, S3 (managed by ACK)
```

### Key Differences from EKS CSOC

| Aspect | Local CSOC | EKS CSOC |
|--------|-----------|---------|
| Cluster | Kind on host | EKS (Terraform-managed) |
| Container | None (host-only) | VS Code DevContainer |
| ACK auth | K8s Secret (`ack-aws-credentials`) | IRSA (no long-lived keys) |
| Deployment | `kind-local-test.sh create install` | `scripts/install.sh apply` |
| Addons config | `argocd/addons/local/addons.yaml` | `argocd/addons/csoc/addons.yaml` |
| Spoke accounts | One (developer's account) | Multiple cross-account |

### Local Bootstrap Chain

```
scripts/kind-local-test.sh create install
    â”‚
    â”œâ”€â”€ kind create cluster --config scripts/kind-config.yaml
    â”œâ”€â”€ helm install argocd (only direct Helm install)
    â”œâ”€â”€ kubectl apply bootstrap ApplicationSets
    â”‚
    â””â”€â”€ ArgoCD reconciles:
         Wave -30: KRO controller
         Wave   1: ACK controllers (â†’ real AWS: ec2, eks, iam, kms, rds, s3, â€¦)
         Wave  10: ResourceGraphDefinitions
         Wave  30: KRO instances
```

### Credential Flow (Local CSOC)

```
Developer runs: bash scripts/mfa-session.sh <MFA_CODE>
    â†’ Writes ~/.aws/credentials [csoc] with STS session token

bash scripts/kind-local-test.sh inject-creds
    â†’ kubectl create secret ack-aws-credentials (in ack-system)
    â†’ ACK controllers pick up credentials on next reconcile
```

See [docs/local-csoc-guide.md](local-csoc-guide.md) for the full step-by-step guide.

