# Gen3 KRO Platform

Deploy your own Gen3 data commons infrastructure using a hub-spoke architecture with Kubernetes Resource Orchestration (KRO), managed by Terraform, Terragrunt, and ArgoCD, all packaged in a ready-to-run development container.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Documentation](#documentation)
- [License](#license)

## Overview

This platform enables you to deploy and manage Gen3 data commons across AWS, Azure, and Google Cloud accounts using a hub-spoke model orchestrated from a central CSOC hub cluster:

- **CSOC Hub Cluster (AWS EKS)**: Central control plane that Terraform/Terragrunt bring up inside the dev container workflow
- **Spoke Clusters**: Provider-specific Kubernetes workloads (AWS, GCP, Azure) running Gen3 applications through KRO graphs
- **Cloud Controllers**: AWS ACK, Google Config Connector (KCC), and Azure Service Operator (ASO) automate infrastructure creation in spoke accounts
- **KRO**: Defines reusable infrastructure graphs that can be instantiated across spokes
- **GitOps**: ArgoCD-driven continuous deployment triggered from branch commits in your Git repository

### Key Features

- 🧰 **Dev Container Workflow**: Repository ships with a dev container that downloads the code and installs Terraform, Terragrunt, ArgoCD, kubectl, and other tooling for you
- 🏗️ **Hub-Spoke Architecture**: Centralized CSOC hub with distributed provider-specific workloads
- 🔐 **IAM Management**: Automated pod identity and cross-account role provisioningz
- ☁️ **Multi-Cloud Orchestration**: Terraform/Terragrunt stand up the AWS CSOC hub, while KRO ResourceGraphDefinitions drive AWS, Azure, and Google Cloud spokes
- 🌐 **Provider Controllers**: Deploy ACK, Google KCC, and Azure Service Operator in the hub to build cloud infrastructure in spoke accounts
- 🔄 **GitOps via ArgoCD**: Branch commits flow into ArgoCD for continuous deployment across clusters
- 🎯 **Resource Graphs**: KRO-powered reusable infrastructure patterns
- 🛡️ **Security First**: IRSA, pod identities, least-privilege IAM policies
- 📊 **Observability**: Built-in metrics and monitoring support

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         HUB CLUSTER                         │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │   ArgoCD    │  │  KRO Engine  │  │ Cloud Controllers  │  │
│  │ (GitOps)    │  │  (RGDs)      │  │  (IAM, EKS, etc.)  │  │
│  └─────────────┘  └──────────────┘  └────────────────────┘  │
│         │                │                      │           │
│         └────────────────┴──────────────────────┘           │
│                          │                                  │
└──────────────────────────┼──────────────────────────────────┘
                           │ GitOps Sync
                           │ (Creates via KRO)
          ┌────────────────┼────────────────┐
          │                │                │
    ┌─────↓─────┐    ┌─────↓─────┐   ┌─────↓─────┐
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

- **Terraform/Terragrunt**: Infrastructure as Code for the AWS-based CSOC hub (VPC, EKS, IAM) executed from the dev container
- **ArgoCD**: Continuous deployment and application lifecycle management
- **KRO**: Kubernetes Resource Orchestrator for defining infrastructure graphs
- **Cloud Provider Controllers**: AWS ACK, Google KCC, and Azure Service Operator manage AWS, Google Cloud, and Azure services directly from the CSOC hub cluster
- **Pod Identities**: IRSA-based authentication for workloads

## Quick Start

```bash
# 1. Fork and clone this repository
git clone https://github.com/YOUR_ORG/gen3-kro.git
cd gen3-kro

# 2. Build the development container (installs Terraform, Terragrunt, ArgoCD CLI, kubectl)
./scripts/docker-build-push.sh

# 3. Customize your configuration
# Edit: live/aws/us-east-1/gen3-kro-hub/terragrunt.hcl
# Update: cluster names, VPC CIDRs, region, etc.

# 4. Deploy your hub cluster
cd live/aws/us-east-1/gen3-kro-hub
terragrunt init
terragrunt plan
terragrunt apply

# 5. Connect to your cluster
aws eks update-kubeconfig --name YOUR_CLUSTER_NAME --region YOUR_REGION

# 6. Verify ArgoCD is running
kubectl get applications -n argocd
```

See the [Getting Started](#getting-started) section for detailed deployment instructions.

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

Before deploying your own Gen3 KRO platform, ensure you have:

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Docker | >= 20.10 | Development environment |
| Git | >= 2.30 | Version control |
| AWS CLI | >= 2.0 | AWS authentication |

**Note**: Terraform, Terragrunt, kubectl, and other tools are included in the Docker container.

### AWS Requirements

- **AWS Account**: With appropriate permissions
- **IAM Permissions**: Ability to create VPCs, EKS clusters, IAM roles/policies, S3 buckets
- **AWS Credentials**: Configured locally (`~/.aws/credentials`)
- **S3 Bucket**: For Terraform state (auto-created on first deployment)
- **DynamoDB Table**: For state locking (optional but recommended)

### Knowledge Prerequisites

Basic familiarity with:
- Kubernetes concepts (pods, services, namespaces)
- Terraform/Infrastructure as Code
- AWS services (VPC, EKS, IAM)
- Git workflows

## Getting Started

Follow these steps to deploy your own Gen3 KRO platform:

### Step 1: Fork and Clone

```bash
# Fork this repository on GitHub to your organization
# Then clone your fork
git clone https://github.com/YOUR_ORG/gen3-kro.git
cd gen3-kro
```

### Step 2: Build Development Environment

```bash
# Build the Docker container with all tools
./scripts/docker-build-push.sh

# Start the container (VS Code)
code .
# Click "Reopen in Container" when prompted

# Or start manually
docker run -it \
  -v $(pwd):/workspace \
  -v ~/.aws:/root/.aws:ro \
  -v ~/.kube:/root/.kube \
  gen3-kro:latest bash
```

See [Docker Setup Guide](docs/setup-docker.md) for detailed instructions.

### Step 3: Customize Configuration

Edit `live/aws/us-east-1/gen3-kro-hub/terragrunt.hcl` to customize:

```hcl
inputs = {
  # Change cluster name
  cluster_name = "my-hub-cluster"

  # Update VPC configuration
  vpc_cidr = "10.0.0.0/16"

  # Configure region
  region = "us-east-1"

  # Update Git repository URL
  argocd_cluster = {
    metadata = {
      annotations = {
        hub_repo_url = "https://github.com/YOUR_ORG/gen3-kro.git"
      }
    }
  }
}
```

### Step 4: Deploy Hub Cluster

```bash
cd live/aws/us-east-1/gen3-kro-hub

# Initialize Terragrunt
terragrunt init

# Review planned changes
terragrunt plan

# Deploy infrastructure (~20-30 minutes)
terragrunt apply
```

See [Terragrunt Deployment Guide](docs/setup-terragrunt.md) for detailed deployment instructions.

### Step 5: Verify Deployment

```bash
# Connect to your cluster
aws eks update-kubeconfig --name my-hub-cluster --region us-east-1

# Check nodes
kubectl get nodes

# Check ArgoCD applications
kubectl get applications -n argocd

# Check provider controllers (namespaces depend on your configuration)
kubectl get pods -n ack-system    # AWS ACK (default namespace)
kubectl get pods -n kcc-system    # Google KCC (if enabled)
kubectl get pods -n aso-system    # Azure Service Operator (if enabled)
```

### Step 6: Deploy Spoke Clusters (Optional)

If deploying multi-account spoke clusters:

1. Create IAM policies for spoke: `iam/gen3/YOUR_SPOKE/`
2. Deploy spoke IAM: `cd live/aws/us-east-1/YOUR_SPOKE-iam && terragrunt apply`
3. Update hub with spoke ARNs
4. Deploy spoke infrastructure via KRO from hub

See [Spoke README](terraform/combinations/spoke/README.md) for detailed spoke deployment.

## Documentation

| Document | Description |
|----------|-------------|
| [Setup Docker](docs/setup-docker.md) | Docker development environment setup |
| [Setup Terragrunt](docs/setup-terragrunt.md) | Infrastructure deployment with Terragrunt |
| [Add Cluster Addons](docs/add-cluster-addons.md) | Adding and configuring cluster addons |
| [Contribution Guide](docs/contributing.md) | Contribution workflow, modular layout, and extension points |
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

## Architecture

The platform uses a hub-spoke model for centralized management:

### Hub-Spoke Model

**Hub Cluster** (Control Plane):
- Runs ArgoCD for GitOps
- Hosts KRO controller
- Provisions spoke infrastructure
- Manages cross-account IAM

**Spoke Deployment**:
- AWS IAM roles created via Terraform (for ACK-managed spokes)
- Provider infrastructure (VPC/EKS, GKE, AKS) created via KRO ResourceGraphs from the hub
- Applications deployed via ArgoCD from hub

### Deployment Waves

ArgoCD deploys in phases:

| Wave | Components | Purpose |
|------|-----------|---------|
| 0 | Platform addons | KRO, provider controllers (ACK/KCC/ASO), External Secrets |
| 1 | ResourceGraphDefinitions | Infrastructure schemas (AWS VPC/EKS, Azure/GCP placeholders) |
| 2 | Graph instances | Actual infrastructure provisioning |
| 3 | Applications | Gen3 data commons workloads |

## Customizing Your Deployment

### Changing Cluster Configuration

Edit your hub terragrunt.hcl to customize:

```hcl
# VPC Configuration
vpc_cidr = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# EKS Configuration
cluster_version = "1.32"
cluster_compute_config = {
  min_size       = 2
  max_size       = 10
  desired_size   = 3
  instance_types = ["t3.large"]
}

# Enable AWS ACK Controllers
ack_configs = {
  ec2 = { enable_pod_identity = true, namespace = "ack-system", service_account = "ack-ec2-sa" }
  eks = { enable_pod_identity = true, namespace = "ack-system", service_account = "ack-eks-sa" }
}
```

### Configuring Provider Controllers

**AWS ACK (built-in today)**
- Create IAM policy: `iam/gen3/csoc/acks/SERVICE_NAME/internal-policy.json`
- Enable in Terragrunt: add the service to `ack_configs`
- Apply changes: `terragrunt apply`

**Google Config Connector (scaffolding provided)**
- Add controller Helm chart information to `argocd/addons/hub/catalog.yaml` and enable it in `argocd/addons/hub/enablement.yaml`
- Provide Google Cloud credentials as Kubernetes secrets referenced by the chart values
- Define KRO ResourceGraphDefinitions under `argocd/graphs/google/` for the resources you want managed

**Azure Service Operator (scaffolding provided)**
- Mirror the pattern from AWS/Google by extending the hub addon catalog with the ASO chart
- Supply Azure service principal credentials as secrets and reference them in addon values
- Define ResourceGraphDefinitions for Azure resources under `argocd/graphs/azure/`

See [Adding Cluster Addons](docs/add-cluster-addons.md) and [Contribution Guide](docs/contributing.md) for detailed instructions on wiring new controllers.

### Deploying to Different Regions

1. Create new directory: `live/aws/YOUR_REGION/YOUR_CLUSTER/`
2. Copy and modify `terragrunt.hcl`
3. Update region-specific configuration
4. Deploy: `terragrunt init && terragrunt apply`

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| ArgoCD app out of sync | `kubectl get application APP_NAME -n argocd -o yaml` |
| Pod identity not working | Check service account annotation: `kubectl describe sa SA_NAME -n NAMESPACE` |
| Terraform state lock | Force unlock: `terragrunt force-unlock LOCK_ID` |
| Provider controller failing | Validate credentials (IAM role, service account secret) and logs: `kubectl logs DEPLOYMENT -n NAMESPACE` |

### Getting Help

- Check [documentation](docs/) for detailed guides
- Review logs in `outputs/logs/` and `outputs/reports/`
- Submit issues on GitHub

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
- [Google Config Connector](https://cloud.google.com/config-connector/docs/overview)
- [Azure Service Operator](https://azure.github.io/azure-service-operator/)
- [Gen3](https://gen3.org/)

---

**Version**: See [`.version`](.version) file
**Last Updated**: October 2025
