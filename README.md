# gen3-kro: Multi-Account EKS Management Platform

> **Hub-and-Spoke Architecture** for cross-account AWS resource provisioning using Terragrunt, ArgoCD, KRO, and AWS Controllers for Kubernetes (ACK).

![Docker CI](https://github.com/indiana-university/gen3-kro/workflows/Docker%20CI/badge.svg)

## 🎯 Overview

gen3-kro is a production-ready platform for managing multiple EKS clusters across AWS accounts using GitOps principles. It implements a hub-and-spoke model where a central hub cluster manages resources across multiple spoke accounts.

### Key Features

- **🏗️ Infrastructure-as-Code**: Terragrunt-based DRY infrastructure with single YAML configuration
- **🔄 GitOps**: ArgoCD-managed declarative application deployment
- **🌐 Multi-Account**: Cross-account resource provisioning via IAM roles
- **🤖 Kubernetes-Native AWS**: AWS Controllers for Kubernetes (ACK) for managing AWS resources
- **📊 Resource Graphs**: KRO (Kubernetes Resource Operator) for complex resource dependencies
- **🐳 CI/CD**: Automated Docker builds with semantic versioning

## 📐 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Hub Cluster                          │
│  ┌────────────┐  ┌──────────┐  ┌─────────────────────┐    │
│  │   ArgoCD   │  │   KRO    │  │  ACK Controllers    │    │
│  │  (GitOps)  │  │ (RGDs)   │  │  (IAM, EKS, EC2...)│    │
│  └────────────┘  └──────────┘  └─────────────────────┘    │
│         │              │                    │               │
│         └──────────────┴────────────────────┘               │
│                        │                                    │
└────────────────────────┼────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   ┌────▼────┐      ┌────▼────┐     ┌────▼────┐
   │ Spoke 1 │      │ Spoke 2 │     │ Spoke N │
   │ (AWS)   │      │ (AWS)   │     │ (AWS)   │
   └─────────┘      └─────────┘     └─────────┘
```

### Components

- **Hub Cluster**: EKS cluster running ArgoCD, KRO, and ACK controllers
- **Spoke Accounts**: External AWS accounts accessed via cross-account IAM roles
- **Terragrunt**: Infrastructure provisioning with DRY configuration
- **ArgoCD**: GitOps-based application deployment and synchronization
- **KRO**: Declarative resource graph definitions for complex dependencies
- **ACK**: Kubernetes-native management of AWS resources

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured with appropriate profiles
- Terraform >= 1.5.0
- Terragrunt >= 0.55.0
- kubectl >= 1.31.0
- Docker (for local development)

### Setup

1. **Configure Infrastructure**:
   ```bash
   # Edit the single configuration file
   vim terraform/config.yaml
   ```

2. **Bootstrap Infrastructure**:
   ```bash
   # Validate configuration
   ./bootstrap/terragrunt-wrapper.sh staging validate
   
   # Plan infrastructure changes
   ./bootstrap/terragrunt-wrapper.sh staging plan
   
   # Apply infrastructure
   ./bootstrap/terragrunt-wrapper.sh staging apply
   ```

3. **Access ArgoCD**:
   ```bash
   # Get ArgoCD admin password
   kubectl get secret argocd-initial-admin-secret \
     -n argocd -o jsonpath="{.data.password}" | base64 -d
   
   # Port forward to ArgoCD UI
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```

4. **Monitor Deployments**:
   ```bash
   # Watch ApplicationSets
   kubectl get applicationsets -n argocd
   
   # Watch Applications
   kubectl get applications -n argocd
   ```

## 📁 Repository Structure

```
gen3-kro/
├── argocd/                    # GitOps manifests and ArgoCD configurations
│   ├── addons/               # Infrastructure components (sync-wave: -1)
│   ├── apps/                 # Application workloads (sync-wave: 3)
│   ├── charts/               # Helm charts for applications
│   ├── fleet/                # KRO resource graph definitions (sync-wave: 0)
│   └── platform/             # Platform services (sync-wave: 1)
│
├── terraform/                 # Infrastructure-as-Code (Terragrunt)
│   ├── config.yaml           # ✅ Single source of truth
│   ├── root.hcl              # Terragrunt root configuration
│   ├── live/                 # Environment-specific configs
│   │   ├── staging/
│   │   └── prod/
│   └── modules/              # Terraform modules
│
├── bootstrap/                 # Operational scripts and automation
│   ├── terragrunt-wrapper.sh # Main CLI for infrastructure operations
│   └── scripts/              # Utility scripts
│       ├── docker-build-push.sh
│       ├── version-bump.sh
│       └── install-git-hooks.sh
│
├── docs/                      # Documentation
│   ├── terragrunt/           # Terragrunt-specific docs
│   ├── argocd/               # ArgoCD-specific docs
│   └── guides/               # How-to guides
│
└── .github/                   # CI/CD workflows and copilot instructions
    ├── workflows/
    └── copilot-instructions.md
```

## 📚 Component Documentation

### Core Components

- **[Terragrunt Infrastructure](terraform/README.md)**: Terragrunt configuration, modules, and operations
- **[ArgoCD GitOps](argocd/README.md)**: ApplicationSets, sync waves, and deployment patterns
- **[CI/CD Pipeline](.github/README.md)**: Docker builds, versioning, and workflows
- **[Bootstrap Scripts](bootstrap/README.md)**: Operational automation and tooling

### Guides

- **[Terragrunt Guide](docs/terragrunt/README.md)**: Infrastructure management
- **[Troubleshooting](docs/terragrunt/troubleshooting.md)**: Common issues and solutions

## 🛠️ Common Operations

### Infrastructure Management

```bash
# Validate configuration
./bootstrap/terragrunt-wrapper.sh staging validate

# Plan infrastructure changes
./bootstrap/terragrunt-wrapper.sh staging plan

# Apply changes
./bootstrap/terragrunt-wrapper.sh staging apply

# Destroy infrastructure (requires confirmation)
./bootstrap/terragrunt-wrapper.sh staging destroy
```

### Application Deployment

```bash
# Deploy via ArgoCD (GitOps)
git add argocd/apps/my-app/
git commit -m "Add new application"
git push

# ArgoCD auto-syncs within 3 minutes
# Or trigger manual sync:
argocd app sync my-app
```

### Monitoring

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Check KRO resource graphs
kubectl get resourcegraphdefinitions -n kro

# Check ACK controllers
kubectl get pods -n ack-system

# View cluster state
k9s
```

## 🔧 Development Workflow

### Making Infrastructure Changes

1. **Edit Configuration**:
   ```bash
   vim terraform/config.yaml
   ```

2. **Validate and Plan**:
   ```bash
   ./bootstrap/terragrunt-wrapper.sh staging validate
   ./bootstrap/terragrunt-wrapper.sh staging plan
   ```

3. **Apply in Staging**:
   ```bash
   ./bootstrap/terragrunt-wrapper.sh staging apply
   ```

4. **Promote to Production**:
   ```bash
   ./bootstrap/terragrunt-wrapper.sh prod plan
   ./bootstrap/terragrunt-wrapper.sh prod apply
   ```

### Adding New Applications

1. **Create Application Manifests**:
   ```bash
   mkdir -p argocd/apps/my-app
   # Add Kubernetes manifests or Helm chart
   ```

2. **Create ArgoCD Application**:
   ```yaml
   # argocd/apps/my-app/application.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: my-app
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: https://github.com/indiana-university/gen3-kro
       targetRevision: main
       path: argocd/apps/my-app
     destination:
       server: https://kubernetes.default.svc
       namespace: my-app
   ```

3. **Commit and Push**:
   ```bash
   git add argocd/apps/my-app/
   git commit -m "Add my-app"
   git push
   ```

## 📝 Configuration

All infrastructure is configured via a single YAML file:

**`terraform/config.yaml`**:
```yaml
hub:
  aws_profile: "boadeyem_tf"
  aws_region: "us-east-1"
  cluster_name: "gen3-kro-hub"

spokes:
  - alias: "spoke1"
    region: "us-east-1"
    profile: "boadeyem_tf"
    account_id: ""

ack:
  controllers:
    - rds
    - eks
    - s3
```

See [Terragrunt README](terraform/README.md) for full configuration options.

## 🆘 Support

- **Documentation**: [docs/](docs/)
- **Troubleshooting**: [docs/terragrunt/troubleshooting.md](docs/terragrunt/troubleshooting.md)
- **Issues**: GitHub Issues

## 📜 License

See [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **AWS EKS Blueprints**: Terraform module patterns
- **ArgoCD**: GitOps deployment platform
- **Terragrunt**: DRY infrastructure configuration
- **KRO**: Kubernetes Resource Operator
- **ACK**: AWS Controllers for Kubernetes

---

**Version**: 0.0.1  
**Last Updated**: October 7, 2025  
**Maintained By**: Indiana University
