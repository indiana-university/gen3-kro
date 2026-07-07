# EKS Cluster Management Platform

> **⚠️ Not for production use.** This platform is under active development and is intended for development, testing, and evaluation purposes only. Infrastructure patterns, APIs, and configuration formats may change without notice between releases.

Multi-account EKS platform using a **CSOC** (Cybersecurity Operations Center) cluster that provisions spoke infrastructure via [KRO](https://github.com/awslabs/kro) + [ACK](https://aws-controllers-k8s.github.io/community/) controllers, orchestrated by [ArgoCD](https://argo-cd.readthedocs.io/) ApplicationSets.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                           CSOC Account                              │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    EKS Cluster ({csoc_alias}-csoc-cluster)       │  │
│  │                                                               │  │
│  │  ┌──────────┐  ┌──────────────┐  ┌────────────────────────┐  │  │
│  │  │  ArgoCD  │  │ KRO          │  │ ACK Controllers (18x)  │  │  │
│  │  │  Server  │→ │ Controller   │→ │ ec2, eks, iam, rds,    │  │  │
│  │  │          │  │              │  │ s3, route53, ...        │  │  │
│  │  └──────────┘  └──────────────┘  └───────────┬────────────┘  │  │
│  │       │                                       │               │  │
│  │       │ ApplicationSets                       │ Cross-account │  │
│  │       ▼                                       │ STS assume    │  │
│  │  ┌──────────────────────┐                     │               │  │
│  │  │ ResourceGraph        │                     │               │  │
│  │  │ Definitions (RGDs)   │                     │               │  │
│  │  └──────────────────────┘                     │               │  │
│  └───────────────────────────────────────────────┼───────────────┘  │
│                                                   │                  │
└───────────────────────────────────────────────────┼──────────────────┘
                                                    │
                    ┌───────────────────────────────┼──────────────┐
                    │                               ▼              │
                    │  ┌─────────────────────────────────────────┐ │
                    │  │   Spoke Account(s)                      │ │
                    │  │   ┌─────────┐  ┌──────┐  ┌──────────┐  │ │
                    │  │   │ VPC     │  │ EKS  │  │ RDS,     │  │ │
                    │  │   │ Subnets │  │      │  │ S3, etc. │  │ │
                    │  │   └─────────┘  └──────┘  └──────────┘  │ │
                    │  └─────────────────────────────────────────┘ │
                    └──────────────────────────────────────────────┘
```

## Key Features

- **Multi-account management** — Single CSOC cluster provisions infrastructure across multiple AWS accounts
- **GitOps-driven** — ArgoCD ApplicationSets reconcile all cluster addons and infrastructure
- **KRO + ACK** — Kubernetes Resource Orchestrator composes ACK resources into reusable infrastructure templates
- **Terragrunt-first deployment** — Terragrunt orchestrates CSOC foundation, spoke IAM, and in-cluster bootstrap; Terraform implements modules
- **Sync wave ordering** — Deterministic deployment: KRO → ACK → RGDs → Instances → Workloads

## Repository Structure

```
├── .devcontainer/                   # VS Code DevContainer (EKS workflow)
├── argocd/                          # GitOps configuration
│   ├── bootstrap/                   #   Entry-point ArgoCD ApplicationSets
│   ├── csoc/                        #   CSOC controllers, Helm charts, KRO RGDs
│   │   ├── controllers/             #     Controller ApplicationSet values
│   │   ├── helm/                    #     Charts used by bootstrap AppSets
│   │   └── kro/                     #     Recursively synced ResourceGraphDefinitions
│   └── spokes/                      #   Per-spoke KRO instance and workload values
├── config/                          # User config files (gitignored except examples)
├── docs/                            # Documentation, diagrams, design reports
├── iam/                             # Per-spoke IAM inline policies
├── references/                      # Upstream reference repos (gen3-helm, kro, etc.)
├── scripts/                         # Deployment and orchestration scripts
├── terraform/
│   ├── env/aws/csoc-cluster/        # Root module (single entry point)
│   └── catalog/
│       ├── modules/                 #   aws-csoc-foundation, csoc-in-cluster-bootstrap,
│       │                            #   csoc-cluster compatibility wrapper, aws-spoke
│       └── units/                   #   Terragrunt unit wrappers
├── terragrunt/live/aws/             # CSOC stack plus deprecated iam-setup compatibility stack
├── outputs/                         # Generated artifacts (gitignored)
└── third-party-licenses/            # Bundled license files
```

See [docs/architecture.md](docs/architecture.md) for detailed architecture documentation with diagrams.

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | 1.13.5 | Infrastructure provisioning (pre-installed in container) |
| Terragrunt | 0.99.1 | Environment orchestration and dependency ordering |
| AWS CLI v2 | 2.32.0 | Cloud authentication and management |
| kubectl | 1.35.1 | Kubernetes cluster interaction |
| Helm | 3.16.1 | Chart templating and validation |
| jq | system | JSON processing |
| Docker | latest | Dev container runtime (host-side) |

## Quick Start

> **Windows users:** The repository must live on a native Linux filesystem (WSL ext4, e.g. `~/src/eks-cluster-mgmt`), **not** `/mnt/c/...`. See [docs/deployment-guide.md](docs/deployment-guide.md).

### 1. Configure Variables

```bash
# Copy the single config file (all variables + backend config)
cp config/shared.auto.tfvars.json.example config/shared.auto.tfvars.json

# Fill in your AWS profiles, cluster name, VPC CIDRs, spoke account IDs, etc.
```

### 2. Authenticate (Host)

```bash
# Option A: Assume CSOC role with MFA (recommended)
bash scripts/mfa-session.sh <MFA_CODE>

# Option B: Copy static credentials from source profile (no MFA)
bash scripts/mfa-session.sh --no-mfa
```

Credentials are written to `~/.aws/eks-devcontainer/credentials [csoc]`.

### 3. Plan CSOC Stack

```bash
bash scripts/csoc-stack.sh plan
```

Review the generated Terragrunt/Terraform plan. The stack order is developer
identity, CSOC AWS foundation, spoke IAM, then in-cluster bootstrap.

For first-time credential bootstrapping without creating the CSOC cluster or
spoke resources, use the prerequisite IAM-only stack:

```bash
bash scripts/prereq-iam.sh plan
bash scripts/prereq-iam.sh apply
```

### 4. Apply CSOC Stack

```bash
bash scripts/csoc-stack.sh apply
```

This creates the AWS foundation, tightens spoke IAM through foundation outputs,
then bootstraps Argo CD into the named CSOC cluster.

### 5. Verify

```bash
kubectl get pods -n argocd          # All pods Running
kubectl get applicationsets -n argocd  # Bootstrap ApplicationSet exists
kubectl get applications -n argocd     # Bootstrap Application created
```

## Local CSOC Quick Start (Host-Based Kind)

Use the local CSOC for RGD authoring and KRO capability testing without EKS overhead.
**No container needed** — runs entirely on the host.

### Prerequisites

Install on host: `kind` 0.27.0, `kubectl`, `helm`, `aws` CLI v2, `docker`.

### 1. Authenticate

```bash
bash scripts/mfa-session.sh <MFA_CODE>
```

### 2. Create Cluster + Install Stack

```bash
bash scripts/kind-csoc.sh create install
```

### 3. Inject Credentials

```bash
bash scripts/kind-csoc.sh inject-creds
```

### 4. Verify

```bash
kubectl get pods --all-namespaces   # All pods Running
kubectl get application -n argocd   # ArgoCD applications synced
kubectl get rgd                     # ResourceGraphDefinitions registered
```

See [docs/local-csoc-guide.md](docs/local-csoc-guide.md) for the full guide.

## Deployment Phases

| Phase | Context | Tool | What |
|-------|---------|------|------|
| **Foundation** | Host or devcontainer | Terragrunt + Terraform | CSOC VPC, EKS, OIDC, and IAM roles |
| **Spoke IAM** | Host or devcontainer | Terragrunt + Terraform | Spoke ACK workload IAM roles with CSOC role trust |
| **Bootstrap** | Host or devcontainer | Terragrunt + Terraform | Argo CD install, repo secrets, cluster secrets, bootstrap ApplicationSet |

The old `terraform/env/aws/csoc-cluster` root and
`terragrunt/live/aws/iam-setup` stack remain compatibility paths until state
migration is complete.

State migration is state-only and must not create resources:

```bash
CONFIRM_STATE_MIGRATION=yes bash scripts/state-migration.sh
```

Run it only after no-apply plans for both the compatibility root and the new
CSOC stack have been reviewed and show no creates, replacements, or deletes.

See [docs/deployment-guide.md](docs/deployment-guide.md) for detailed deployment procedures.

## Teardown

```bash
# Destroy CSOC stack and all Terraform-managed resources
bash scripts/csoc-stack.sh destroy

# Deprecated compatibility path for pre-migration IAM state
cd terragrunt/live/aws/iam-setup
terragrunt stack run destroy
```

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | Detailed architecture with diagrams |
| [Deployment Guide](docs/deployment-guide.md) | Step-by-step deployment procedures |
| [Local CSOC Guide](docs/local-csoc-guide.md) | Host-based Kind cluster setup and operations |
| [Security Model](docs/security.md) | IAM, cross-account trust, credentials |
| [ArgoCD Configuration](argocd/README.md) | GitOps structure and conventions |
| [Contributing](CONTRIBUTING.md) | Branching, code quality, PR process |

## Project Conventions

- **CSOC** — replaces "hub" in all documentation and configuration
- **WSL ext4** — repo must live on a native Linux filesystem, not `/mnt/c/...`
- **Config** — `config/shared.auto.tfvars.json` (gitignored); single source of truth for all Terraform + Terragrunt config
- **SSM secrets** — `config/ssm-repo-secrets/input.json` (gitignored); copy from `input.json.example`
- **IAM policies** — file-driven: `iam/<spoke>/ack/inline-policy.json` with `iam/_default/` fallback
- **Sync waves** — enforce deployment ordering (negative = first, higher = later)
- **Management modes** — `self_managed` (Helm via ArgoCD) or `aws_managed` (EKS Capabilities)
- **Compatibility wrapper** — `terraform/env/aws/csoc-cluster/` still calls `csoc-cluster` until state migration completes

## License

Internal use — Indiana University Research Data Services.
