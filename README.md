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
│  │  │  ArgoCD  │  │ KRO          │  │ ACK Controllers        │  │  │
│  │  │  Server  │→ │ Controller   │→ │ cloudtrail, ec2, efs,  │  │  │
│  │  │          │  │              │  │ eks, iam, rds, s3, ... │  │  │
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
├── .devcontainer/                   # Dev Container configuration and Dockerfile
├── argocd/                          # GitOps configuration
│   ├── bootstrap/                   #   Entry-point ArgoCD ApplicationSets
│   ├── csoc/                        #   CSOC controllers, Helm charts, KRO RGDs
│   │   ├── controllers/             #     Controller ApplicationSet values
│   │   ├── helm/                    #     Charts: csoc-controllers, kro-aws-instances, multi-account
│   │   └── kro/aws-rgds/            #     ResourceGraphDefinitions (gen3/, test/)
│   └── spokes/                      #   Per-spoke KRO instance and workload values
├── config/                          # User config files (gitignored except examples)
├── docs/                            # Architecture, deployment, security documentation
├── iam/                             # Per-spoke and operator-role IAM policy sources
├── plan/                            # Architecture decisions, migration roadmap, target operating model
├── references/                      # Upstream reference repos (gen3-helm, gen3-gitops, gen3-build, awesome-copilot)
├── scripts/                         # Deployment and orchestration scripts
├── terraform/
│   └── catalog/
│       ├── modules/                 #   7 Terraform modules (cluster, IAM, ArgoCD install, gitops bootstrap)
│       └── units/                   #   7 Terragrunt unit wrappers
├── terragrunt/live/aws/             # operators-iam, csoc-cluster-core, and spoke-fleet-update stacks
├── outputs/                         # Generated artifacts (gitignored)
└── third-party-licenses/            # Bundled license files
```

See [docs/architecture.md](docs/architecture.md) for detailed architecture documentation with diagrams.

## Prerequisites

### Host (install before opening the container)

| Tool | Version | Purpose |
|------|---------|--------|
| Docker | latest | Dev container runtime |
| VS Code + Dev Containers extension | latest | Container environment |
| AWS CLI v2 | 2.x | `mfa-session.sh` credential writing |
| Terragrunt | 1.1.1 | Required only when running Terragrunt stacks outside the container |

### Container (pre-installed in devcontainer)

| Tool | Version | Purpose |
|------|---------|--------|
| Terraform | 1.15.8 | Infrastructure provisioning |
| Terragrunt | 1.1.1 | Environment orchestration |
| AWS CLI v2 | 2.32.0 | Cloud authentication and management |
| kubectl | 1.35.1 | Kubernetes cluster interaction |
| Helm | 3.16.1 | Chart templating and validation |
| jq | system | JSON processing |
| yq | 4.44.3 | YAML processing |
| kustomize | 5.7.1 | Kubernetes manifest overlays |
| ArgoCD CLI | latest | ArgoCD operations |
| k9s | latest | Kubernetes TUI |

## Quick Start

> **Windows users:** The repository must live on a native Linux filesystem (WSL ext4, e.g. `~/src/eks-cluster-mgmt`), **not** `/mnt/c/...`. See [docs/deployment-guide.md](docs/deployment-guide.md).

### AWS Prerequisites (must exist before first run)

The following AWS resources must be created manually before Terragrunt can run:

| Resource | Account | Purpose |
|----------|---------|---------|
| S3 bucket | CSOC | Terraform remote state backend — set `backend_bucket` in config |
| IAM user | CSOC | Your operator identity used as the MFA source profile |
| GitHub App | GitHub | ArgoCD git authentication (**private repos only** — skip if your GitOps repo is public) |

The S3 bucket requires versioning enabled and a bucket policy that allows the
operator IAM role (`{csoc_alias}-csoc-operator-infrastructure-admin`) to
read/write objects.
For private repos, the GitHub App needs read access to all repos listed in
`config/ssm-repo-secrets/input.json`. See [scripts/ssm-repo-secrets/README.md](scripts/ssm-repo-secrets/README.md).

### Step 0 — Operator IAM Bootstrap (one-time per operator)

This step references an existing IAM user and creates function-specific,
MFA-gated operator roles. Terraform may manage a virtual MFA device but never
the IAM user.

**a. Copy and populate the config file:**

```bash
cp config/shared.auto.tfvars.json.example config/shared.auto.tfvars.json
```

Minimum fields to fill before running `operators-iam`:

```json
{
  "backend_bucket":  "my-terraform-state-bucket",
  "backend_region":  "us-east-1",
  "region":          "us-east-1",
  "aws_profile":     "<YOUR_ADMIN_AWS_PROFILE>",
  "csoc_account_id": "<CSOC_ACCOUNT_ID>",
  "csoc_alias":      "rds-gen3"
}
```

**b. Review and create operator IAM:**

```bash
bash scripts/terragrunt-stack.sh operators-iam plan   # review first
bash scripts/terragrunt-stack.sh operators-iam apply
```

After apply, run `bash scripts/operator-profile.sh` to write structured
non-secret role/MFA mappings. See
[scripts/terragrunt-stack.md](scripts/terragrunt-stack.md) for stack/command
reference.

**c. Register and activate a newly created virtual MFA device** using the
sensitive `mfa_enrollment` output, then select a role with
`bash scripts/mfa-session.sh <MFA_CODE> --role-key infrastructure-admin`.

### Step 1 — Populate Config

Complete all remaining fields in `config/shared.auto.tfvars.json`. Groups to fill in:
VPC CIDRs, GitHub org/repo, ArgoCD chart version, SSM secret names (private repos only),
and spoke account aliases. See `config/shared.auto.tfvars.json.example` for the full schema.

### Step 2 — Push SSM Repo Secrets (private repos only)

> Skip this step if your GitOps repo is public.

ArgoCD needs GitHub App credentials in AWS Secrets Manager before the fleet
stack runs. See [scripts/ssm-repo-secrets/README.md](scripts/ssm-repo-secrets/README.md)
for the full input schema and push workflow.

```bash
cp config/ssm-repo-secrets/input.json.example config/ssm-repo-secrets/input.json
# Fill in GitHub App credentials, then:
bash scripts/ssm-repo-secrets/generate-ssm-payload.sh
bash scripts/ssm-repo-secrets/push-ssm-secrets.sh
```

### Step 3 — Authenticate (Host)

Run on the **host** before opening the devcontainer (or before each 12-hour
session expiry). See [scripts/mfa-session.md](scripts/mfa-session.md) for
options, error reference, and how auto-detection of role/serial works.

```bash
bash scripts/mfa-session.sh <MFA_CODE>       # MFA assumed-role (recommended)
bash scripts/mfa-session.sh --no-mfa         # Copy admin profile credentials
```

### Step 4 — Open the Devcontainer

In VS Code: `Cmd/Ctrl+Shift+P` → **Dev Containers: Reopen in Container**

The container mounts `~/.aws/eks-devcontainer` and sets `AWS_PROFILE=csoc`
automatically. See [scripts/container-init.md](scripts/container-init.md) for
what the init script validates and how credential tiers are reported.

### Step 5 — Plan and Apply CSOC Stack

```bash
bash scripts/terragrunt-stack.sh csoc-cluster-core plan
bash scripts/terragrunt-stack.sh csoc-cluster-core apply
```

Creates the CSOC VPC/EKS cluster, controller IAM, and Argo CD installation.
See [scripts/terragrunt-stack.md](scripts/terragrunt-stack.md) for unit-level
targeting and state key reference.

### Step 6 — Apply Fleet Stack

```bash
TG_SPOKE_ALIAS=spoke1 bash scripts/terragrunt-stack.sh spoke-fleet-update plan
TG_SPOKE_ALIAS=spoke1 bash scripts/terragrunt-stack.sh spoke-fleet-update apply
```

Creates per-spoke IAM, CSOC assume-role access, and the bootstrap
ApplicationSet that registers the spoke with ArgoCD.

### Step 7 — Verify

```bash
kubectl get pods -n argocd             # All pods Running
kubectl get applicationsets -n argocd  # Bootstrap ApplicationSet exists
kubectl get applications -n argocd     # Bootstrap Application created
kubectl get rgd                        # ResourceGraphDefinitions registered
```

## Local CSOC Quick Start (Host-Based Kind)

Use the local CSOC for RGD authoring and KRO capability testing without EKS overhead.
**No container needed** — runs entirely on the host.
See [scripts/kind-csoc.md](scripts/kind-csoc.md) for stage reference and bootstrap
wave ordering, or [docs/local-csoc-guide.md](docs/local-csoc-guide.md) for the
full walkthrough.

```bash
bash scripts/mfa-session.sh <MFA_CODE>         # Refresh credentials on host
bash scripts/kind-csoc.sh create install       # Create cluster + full stack
bash scripts/kind-csoc.sh inject-creds         # Refresh ACK creds if needed
```

Verify:

```bash
kubectl get pods --all-namespaces   # All pods Running
kubectl get application -n argocd   # ArgoCD applications synced
kubectl get rgd                     # ResourceGraphDefinitions registered
```

## Deployment Phases

| Phase | Context | Tool | What |
|-------|---------|------|------|
| **operators-iam** | Host | Terragrunt + Terraform | Existing-user MFA and function-specific operator roles |
| **csoc-cluster-core** | Host or devcontainer | Terragrunt + Terraform | CSOC VPC/EKS, controller IAM, and Argo CD install |
| **spoke-fleet-update** | Host or devcontainer | Terragrunt + Terraform | Per-spoke IAM, cross-account trust, and GitOps bootstrap |

For per-unit state keys, log paths, and unit-level targeting, see
[scripts/terragrunt-stack.md](scripts/terragrunt-stack.md).
For full step-by-step procedures, see [docs/deployment-guide.md](docs/deployment-guide.md).

## Teardown

```bash
# Destroy CSOC stack and all Terraform-managed resources
bash scripts/terragrunt-stack.sh csoc-cluster-core destroy
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update destroy

# Destroy operator IAM only when intentionally removing all managed operator access
bash scripts/terragrunt-stack.sh operators-iam destroy
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

### Script Reference

| Script | Description |
|--------|-------------|
| [scripts/mfa-session.md](scripts/mfa-session.md) | Write devcontainer AWS credentials (host) |
| [scripts/container-init.md](scripts/container-init.md) | Devcontainer setup and credential tiers |
| [scripts/terragrunt-stack.md](scripts/terragrunt-stack.md) | Terragrunt stack/unit reference and log paths |
| [scripts/kind-csoc.md](scripts/kind-csoc.md) | Local Kind CSOC stages and bootstrap order |
| [scripts/ssm-repo-secrets/README.md](scripts/ssm-repo-secrets/README.md) | GitHub App credentials → AWS Secrets Manager |

## Project Conventions

- **CSOC** — replaces "hub" in all documentation and configuration
- **WSL ext4** — repo must live on a native Linux filesystem, not `/mnt/c/...`
- **Config** — `config/shared.auto.tfvars.json` (gitignored); single source of truth for all Terraform + Terragrunt config
- **SSM secrets** — `config/ssm-repo-secrets/input.json` (gitignored); copy from `input.json.example`
- **IAM policies** — file-driven: `iam/<spoke>/ack/inline-policy.json` with `iam/_default/` fallback
- **Sync waves** — enforce deployment ordering (negative = first, higher = later)
- **Management modes** — `self_managed` (Helm via ArgoCD) or `aws_managed` (EKS Capabilities)
- **State ownership** — Terragrunt units own stable split state keys; do not reintroduce a combined root state

## License

Internal use — Indiana University Research Data Services.
