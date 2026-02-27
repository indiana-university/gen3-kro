# EKS Cluster Management Platform

Multi-account EKS platform using a **CSOC** (Cybersecurity Operations Center) cluster that provisions spoke infrastructure via [KRO](https://github.com/awslabs/kro) + [ACK](https://aws-controllers-k8s.github.io/community/) controllers, orchestrated by [ArgoCD](https://argo-cd.readthedocs.io/) ApplicationSets.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                           CSOC Account                              │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    EKS Cluster ({csoc_alias}-csoc-cluster)       │  │
│  │                                                               │  │
│  │  ┌──────────┐  ┌──────────────┐  ┌────────────────────────┐  │  │
│  │  │  ArgoCD  │  │ KRO          │  │ ACK Controllers (17x)  │  │  │
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
- **Two-phase deployment** — Host-side Terragrunt for spoke IAM, container-side Terraform for CSOC EKS + ArgoCD
- **Sync wave ordering** — Deterministic deployment: KRO → ACK → RGDs → Instances → Workloads

## Repository Structure

```
├── argocd/                      # GitOps configuration
│   ├── bootstrap/               #   Entry-point ApplicationSets
│   ├── addons/                  #   Addon values (CSOC + environments)
│   ├── charts/                  #   Helm charts consumed by ApplicationSets
│   └── cluster-fleet/           #   Per-cluster overrides
├── config/                      # User config files (gitignored except examples)
├── terraform/
│   ├── env/aws/csoc-cluster/    # Root module (single entry point)
│   └── catalog/
│       ├── modules/             #   csoc-cluster, aws-csoc, argocd-bootstrap, aws-spoke
│       └── units/               #   Terragrunt unit wrappers (host-only)
├── terragrunt/live/aws/         # Spoke IAM Terragrunt stack (host-only, iam-setup/)
├── iam/                         # Per-spoke IAM inline policies
├── scripts/                     # Deployment scripts
├── docs/                        # Documentation and diagrams
└── outputs/                     # Generated artifacts (gitignored)
```

See [docs/architecture.md](docs/architecture.md) for detailed architecture documentation with diagrams.

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | 1.13.5 | Infrastructure provisioning (pre-installed in container) |
| Terragrunt | 0.99.1 | Spoke IAM role management (host-side only) |
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

### 3. Deploy Spoke IAM Roles (Host)

```bash
cd terragrunt/live/aws/iam-setup
terragrunt stack run init
terragrunt stack run apply
```

### 4. Deploy CSOC Cluster (Container)

```bash
# Inside dev container or WSL with AWS credentials
bash scripts/install.sh apply
```

This single command:
1. Runs `terraform init` with backend config extracted from `config/shared.auto.tfvars.json`
2. Runs `terraform apply` — creates EKS cluster, VPC, ArgoCD, ACK roles, bootstrap ApplicationSet
3. Configures kubeconfig and retrieves ArgoCD admin password

### 5. Verify

```bash
kubectl get pods -n argocd          # All pods Running
kubectl get applicationsets -n argocd  # Bootstrap ApplicationSet exists
kubectl get applications -n argocd     # Bootstrap Application created
```

## Deployment Phases

| Phase | Context | Tool | What |
|-------|---------|------|------|
| **Phase 1** | Host machine | Terragrunt | Spoke ACK workload IAM roles (cross-account) |
| **Phase 2** | Container/WSL | Terraform | CSOC EKS cluster + VPC + ArgoCD + bootstrap |

See [docs/deployment-guide.md](docs/deployment-guide.md) for detailed deployment procedures.

## Teardown

```bash
# Destroy CSOC cluster and all Terraform-managed resources
bash scripts/destroy.sh

# Destroy spoke IAM roles (from host)
cd terragrunt/live/aws/iam-setup
terragrunt stack run destroy
```

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | Detailed architecture with diagrams |
| [Deployment Guide](docs/deployment-guide.md) | Step-by-step deployment procedures |
| [Security Model](docs/security.md) | IAM, cross-account trust, credentials |
| [ArgoCD Configuration](argocd/README.md) | GitOps structure and conventions |
| [Dev Container](.devcontainer/README.md) | Development environment setup |

## Project Conventions

- **CSOC** — replaces "hub" in all documentation and configuration
- **WSL ext4** — repo must live on a native Linux filesystem, not `/mnt/c/...`
- **Config** — `config/shared.auto.tfvars.json` (gitignored); single source of truth for all Terraform + Terragrunt config
- **SSM secrets** — `config/ssm-repo-secrets/input.json` (gitignored); copy from `input.json.example`
- **IAM policies** — file-driven: `iam/<spoke>/ack/inline-policy.json` with `iam/_default/` fallback
- **Sync waves** — enforce deployment ordering (negative = first, higher = later)
- **Management modes** — `self_managed` (Helm via ArgoCD) or `aws_managed` (EKS Capabilities)
- **Single root module** — `terraform/env/aws/csoc-cluster/` calls composite `csoc-cluster` module

## License

Internal use — Indiana University Research Data Services.
