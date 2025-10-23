# Gen3 KRO Platform

A Kubernetes Resource Orchestration (KRO) platform for deploying and managing Gen3 data commons infrastructure using a hub-spoke architecture with Terraform, Terragrunt, and ArgoCD.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Overview

The Gen3 KRO Platform enables centralized management and deployment of Gen3 data commons across multiple AWS accounts and Kubernetes clusters. It implements a hub-spoke model where:

- **Hub Cluster**: Central control plane that manages infrastructure provisioning, policy orchestration, and GitOps operations
- **Spoke Clusters**: Workload clusters running Gen3 applications and services
- **KRO (Kubernetes Resource Orchestrator)**: Defines reusable infrastructure graphs that can be instantiated across spokes
- **GitOps**: ArgoCD-driven continuous deployment from Git repositories

### Key Features

- 🏗️ **Hub-Spoke Architecture**: Centralized management with distributed workloads
- 🔐 **IAM Management**: Automated pod identity and cross-account role provisioning
- ☁️ **Multi-Cloud Ready**: Designed for AWS, extensible to Azure and GCP
- 📦 **ACK Integration**: AWS Controllers for Kubernetes (ACK) for native AWS resource management
- 🔄 **GitOps Enabled**: ArgoCD-based continuous deployment
- 🎯 **Resource Graphs**: KRO-powered reusable infrastructure patterns
- 🛡️ **Security First**: IRSA, pod identities, least-privilege IAM policies
- 📊 **Observability**: Built-in metrics and monitoring support

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         HUB CLUSTER                              │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐     │
│  │   ArgoCD    │  │  KRO Engine  │  │  ACK Controllers   │     │
│  │ (GitOps)    │  │  (RGDs)      │  │  (IAM, EKS, etc.)  │     │
│  └─────────────┘  └──────────────┘  └────────────────────┘     │
│         │                │                      │                │
│         └────────────────┴──────────────────────┘                │
│                          │                                       │
└──────────────────────────┼───────────────────────────────────────┘
                           │ GitOps Sync
                           │ (Creates via KRO)
          ┌────────────────┼────────────────┐
          │                │                │
    ┌─────▼─────┐    ┌─────▼─────┐   ┌─────▼─────┐
    │ SPOKE 1   │    │ SPOKE 2   │   │ SPOKE N   │
    │ (IAM Only)│    │ (IAM Only)│   │ (IAM Only)│
    │           │    │           │   │           │
    │ Roles +   │    │ Roles +   │   │ Roles +   │
    │ Policies  │    │ Policies  │   │ Policies  │
    └───────────┘    └───────────┘   └───────────┘
          ↓                ↓                ↓
    ┌───────────┐    ┌───────────┐   ┌───────────┐
    │ Spoke VPC │    │ Spoke VPC │   │ Spoke VPC │
    │ Spoke EKS │    │ Spoke EKS │   │ Spoke EKS │
    │ Gen3 Apps │    │ Gen3 Apps │   │ Gen3 Apps │
    │(via KRO)  │    │(via KRO)  │   │(via KRO)  │
    └───────────┘    └───────────┘   └───────────┘

Note: Spoke Terraform compositions only create IAM roles/policies.
      Spoke clusters and Gen3 apps are provisioned via KRO from hub.
```

### Component Overview

- **Terraform/Terragrunt**: Infrastructure as Code for AWS resources, VPCs, EKS clusters, and IAM
- **ArgoCD**: Continuous deployment and application lifecycle management
- **KRO**: Kubernetes Resource Orchestrator for defining infrastructure graphs
- **ACK Controllers**: Manage AWS services directly from Kubernetes
- **Pod Identities**: IRSA-based authentication for workloads

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/indiana-university/gen3-kro.git
cd gen3-kro

# 2. Build the development container
./scripts/docker-build-push.sh

# 3. Deploy the hub cluster
cd live/aws/us-east-1/gen3-kro-hub
terragrunt init
terragrunt plan
terragrunt apply

# 4. Connect to the cluster
../../../../../../scripts/connect-cluster.sh gen3-kro-hub

# 5. Verify ArgoCD is running
kubectl get applications -n argocd
```

For detailed setup instructions, see:
- [Docker Setup Guide](docs/setup-docker.md)
- [Terragrunt Deployment Guide](docs/setup-terragrunt.md)

## Repository Structure

```
.
├── argocd/                    # ArgoCD applications and configuration
│   ├── bootstrap/            # Bootstrap ApplicationSets (Wave 0-3)
│   ├── hub/                  # Hub cluster addon configurations
│   ├── spokes/               # Spoke cluster configurations
│   ├── graphs/               # KRO ResourceGraphDefinitions
│   └── plans/                # Deployment planning documents
├── docs/                      # Documentation
│   ├── diagrams/             # Architecture diagrams (.drawio)
│   ├── setup-docker.md       # Docker setup guide
│   ├── setup-terragrunt.md   # Terragrunt deployment guide
│   ├── add-cluster-addons.md # Adding addons guide
│   └── version-bump.md       # Version management guide
├── iam/                       # IAM policy definitions
│   └── gen3/                 # Gen3-specific policies
│       ├── csoc/             # Hub (CSOC) policies
│       └── spoke1/           # Spoke-specific policies
├── live/                      # Terragrunt live configurations
│   └── aws/us-east-1/        # AWS region deployments
│       └── gen3-kro-hub/     # Hub cluster Terragrunt config
├── scripts/                   # Utility scripts
│   ├── connect-cluster.sh    # Cluster connection helper
│   ├── docker-build-push.sh  # Docker build automation
│   └── version-bump.sh       # Version management
├── terraform/                 # Terraform modules
│   ├── combinations/         # Composition modules (hub, spoke)
│   │   ├── hub/             # Hub cluster composition
│   │   └── spoke/           # Spoke IAM composition
│   └── modules/             # Reusable Terraform modules
│       ├── argocd/          # ArgoCD installation
│       ├── eks-cluster/     # EKS cluster provisioning
│       ├── pod-identity/    # Pod identity management
│       ├── vpc/             # VPC networking
│       ├── iam-policy/      # IAM policy loading
│       ├── cross-account-policy/ # Cross-account policies
│       ├── spoke-role/      # Spoke IAM roles
│       └── spokes-configmap/ # ArgoCD ConfigMap generator
└── outputs/                   # Generated reports and logs
    ├── logs/                 # Execution logs
    └── reports/              # Verification reports
```

## Prerequisites

### Required Tools

- **Docker**: For containerized development environment
- **Terraform**: >= 1.5.0
- **Terragrunt**: >= 0.48.0
- **kubectl**: >= 1.28
- **AWS CLI**: >= 2.0
- **Git**: >= 2.30

### AWS Requirements

- AWS account with appropriate permissions
- AWS CLI configured with credentials
- IAM permissions to create:
  - VPCs, subnets, route tables
  - EKS clusters
  - IAM roles and policies
  - KMS keys
  - S3 buckets (for Terraform state)

### Knowledge Prerequisites

- Kubernetes fundamentals
- Terraform/Terragrunt basics
- AWS IAM and networking concepts
- Git and GitOps principles

## Getting Started

### 1. Environment Setup

See the [Docker Setup Guide](docs/setup-docker.md) for instructions on:
- Building the development container
- Configuring the dev environment
- Required environment variables

### 2. Deploy Hub Cluster

See the [Terragrunt Deployment Guide](docs/setup-terragrunt.md) for:
- Hub cluster deployment
- Spoke IAM provisioning
- ArgoCD bootstrapping
- Verification steps

### 3. Add Cluster Addons

See the [Adding Cluster Addons Guide](docs/add-cluster-addons.md) for:
- Enabling ACK controllers
- Adding platform addons
- Configuring IAM roles
- Updating ArgoCD configurations

### 4. Deploy Spoke Clusters

Follow the deployment guide to:
- Create spoke IAM roles and policies
- Deploy spoke infrastructure via KRO
- Register spokes with ArgoCD
- Deploy Gen3 applications

## Documentation

| Document | Description |
|----------|-------------|
| [Setup Docker](docs/setup-docker.md) | Docker development environment setup |
| [Setup Terragrunt](docs/setup-terragrunt.md) | Infrastructure deployment with Terragrunt |
| [Add Cluster Addons](docs/add-cluster-addons.md) | Adding and configuring cluster addons |
| [Version Bump](docs/version-bump.md) | Semantic versioning and release management |
| [Terraform Hub](terraform/combinations/hub/README.md) | Hub cluster Terraform composition |
| [Terraform Spoke](terraform/combinations/spoke/README.md) | Spoke IAM Terraform composition |
| [Terraform Modules](terraform/modules/README.md) | Reusable Terraform modules documentation |
| [ArgoCD Structure](argocd/README.md) | ArgoCD configuration and ApplicationSets |

### Architecture Diagrams

See `docs/diagrams/` for:
- Hub-spoke architecture overview
- Deployment sequence flow
- IAM policy flow
- ArgoCD ApplicationSet hierarchy

## Core Concepts

### Hub-Spoke Model

The platform uses a centralized hub cluster that manages multiple spoke environments:

- **Hub Cluster**:
  - Runs ArgoCD for GitOps
  - Hosts KRO controller and ResourceGraphDefinitions
  - Provisions spoke infrastructure via KRO
  - Manages cross-account IAM policies

- **Spoke Terraform Composition** (IAM Only):
  - Creates IAM roles with trust policies to hub
  - Loads IAM policies from `iam/` directory
  - Manages cross-account role assumptions
  - Does NOT create VPCs, EKS clusters, or workloads

- **Spoke Infrastructure** (Created via KRO from Hub):
  - VPCs, EKS clusters, and networking
  - Gen3 application workloads
  - Kubernetes resources and ACK instances
  - Deployed via ArgoCD ApplicationSets from hub

### IAM Policy Flow

The system handles three IAM scenarios:

1. **Hub-Internal**: Spoke account = Hub account
   - Hub pod identity attaches internal policies directly
   - Spoke composition is NOT used
   - All resources in single AWS account

2. **Cross-Account**: Spoke account ≠ Hub account
   - Hub: Pod identity with AssumeRole policy
   - Spoke: IAM role (created by spoke composition) with trust to hub
   - Hub ACK controllers assume spoke roles to manage spoke resources

3. **Override ARNs**: Pre-existing roles in spoke account
   - Spoke composition skips role creation
   - Uses externally managed roles
   - ARNs passed to hub for cross-account policies

### GitOps Deployment Waves

ArgoCD deploys applications in waves:

- **Wave 0**: Platform addons (KRO, ACK, External Secrets)
- **Wave 1**: ResourceGraphDefinitions (infrastructure schemas)
- **Wave 2**: Graph instances (infrastructure provisioning)
- **Wave 3**: Application workloads (Gen3 commons)

## Development Workflow

### Making Changes

1. **Update Configuration**: Modify Terraform, ArgoCD, or IAM configs
2. **Plan Changes**: Run `terragrunt plan` to preview
3. **Apply Changes**: Run `terragrunt apply` to deploy
4. **Verify Sync**: Check ArgoCD applications sync successfully
5. **Commit Changes**: Push to Git for GitOps tracking

### Testing

```bash
# Initialize Terragrunt
cd live/aws/us-east-1/gen3-kro-hub
terragrunt init

# Plan infrastructure changes
terragrunt plan

# Apply and show full output
terragrunt apply

# Validate ArgoCD applications
kubectl get applications -n argocd
kubectl get applicationsets -n argocd
```

### Version Management

See [Version Bump Guide](docs/version-bump.md) for:
- Semantic versioning strategy
- Automated version bumping
- Release tagging process

## Troubleshooting

### Common Issues

**ArgoCD application out of sync**:
```bash
kubectl get application <app-name> -n argocd -o yaml
# Check sync status and error messages
```

**Pod identity not working**:
```bash
kubectl describe sa <service-account> -n <namespace>
# Verify eks.amazonaws.com/role-arn annotation
```

**Terraform state lock**:
```bash
# Check S3 backend for lock file
aws s3 ls s3://<state-bucket>/locks/
```

### Logs and Reports

Execution logs and verification reports are saved to:
- `outputs/logs/`: Terraform and script logs
- `outputs/reports/`: Verification and completion reports

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes following the repository structure
4. Test changes in a dev environment
5. Submit a pull request with detailed description

### Code Standards

- Follow Terraform best practices
- Use Terragrunt for DRY configurations
- Document all modules and variables
- Write clear commit messages
- Update relevant documentation

## License

See [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or contributions:
- GitHub Issues: [github.com/indiana-university/gen3-kro/issues](https://github.com/indiana-university/gen3-kro/issues)
- Documentation: [docs/](docs/)

## Acknowledgments

Built using:
- [Terraform](https://www.terraform.io/)
- [Terragrunt](https://terragrunt.gruntwork.io/)
- [ArgoCD](https://argo-cd.readthedocs.io/)
- [KRO](https://kro.run/)
- [AWS Controllers for Kubernetes (ACK)](https://aws-controllers-k8s.github.io/community/)
- [Gen3](https://gen3.org/)

---

**Version**: See [`.version`](.version) file
**Last Updated**: October 2025
