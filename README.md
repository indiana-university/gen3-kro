# gen3-kro v0.1.0

**Multi-Account EKS Management Platform with Hub-Spoke Architecture**

[![Docker CI](https://github.com/indiana-university/gen3-kro/workflows/Docker%20CI/badge.svg)](https://github.com/indiana-university/gen3-kro/actions)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Terraform](https://img.shields.io/badge/Terraform-1.5+-purple.svg)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.31+-blue.svg)](https://kubernetes.io/)

> Production-ready platform for managing multiple EKS clusters across AWS accounts using GitOps, Terragrunt, ArgoCD, and KRO.

## Overview

gen3-kro provides a complete solution for deploying and managing Kubernetes infrastructure across multiple AWS accounts using a hub-and-spoke model. The hub cluster orchestrates infrastructure provisioning and application deployments to spoke clusters using Kubernetes-native tools.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Hub Cluster (EKS)                      │
│                                                             │
│  ┌──────────┐  ┌─────────┐  ┌──────┐  ┌───────────────┐  │
│  │ ArgoCD   │  │   KRO   │  │ ACK  │  │  Terraform/   │  │
│  │ (GitOps) │  │ (RGDs)  │  │      │  │  Terragrunt   │  │
│  └──────────┘  └─────────┘  └──────┘  └───────────────┘  │
│         │             │          │              │          │
└─────────┼─────────────┼──────────┼──────────────┼──────────┘
          │             │          │              │
    ┌─────▼─────┬──────▼──────┬───▼──────┬──────▼──────┐
    │           │             │          │             │
┌───▼───┐   ┌───▼───┐     ┌───▼───┐  ┌───▼───┐    ┌───▼───┐
│Spoke 1│   │Spoke 2│ ... │Spoke N│  │ Apps  │    │ Infra │
│(EKS)  │   │(EKS)  │     │(EKS)  │  │       │    │       │
└───────┘   └───────┘     └───────┘  └───────┘    └───────┘
```

### Key Components

- **Hub Cluster**: Central EKS cluster hosting control plane components
- **Spoke Clusters**: Target EKS clusters deployed via KRO Resource Graphs
- **ArgoCD**: GitOps continuous delivery for Kubernetes
- **KRO**: Kubernetes Resource Operator for complex resource graphs
- **ACK**: AWS Controllers for Kubernetes (optional)
- **Terragrunt/Terraform**: Infrastructure-as-Code for hub deployment

## Features

✅ **Hub-Spoke Architecture**: Centralized management of multiple clusters  
✅ **GitOps Workflow**: Declarative infrastructure and applications  
✅ **Resource Graphs**: Complex dependencies via KRO ResourceGraphDefinitions  
✅ **Multi-Account**: Cross-account AWS resource provisioning  
✅ **Single Config**: Centralized YAML configuration (`config/config.yaml`)  
✅ **Validation Scripts**: Automated testing and validation  
✅ **Documentation**: Comprehensive guides and examples  

## Quick Start

### Prerequisites

- AWS CLI configured
- Terraform >= 1.5.0
- Terragrunt >= 0.55.0
- kubectl >= 1.31.0
- kustomize >= 5.0.0
- Docker (optional, for container builds)

### 1. Deploy Hub Infrastructure

```bash
# Validate configuration
./bootstrap/terragrunt-wrapper.sh staging validate

# Plan changes
./bootstrap/terragrunt-wrapper.sh staging plan

# Apply infrastructure
./bootstrap/terragrunt-wrapper.sh staging apply
```

### 2. Bootstrap Hub ArgoCD

```bash
# Apply hub bootstrap
kubectl apply -k hub/argocd/bootstrap/overlays/staging

# Verify ArgoCD is running
kubectl get pods -n argocd

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### 3. Deploy Spoke Clusters (Optional)

```bash
# Create spoke from template
cp -r spokes/spoke-template spokes/my-spoke

# Configure spoke
vi spokes/my-spoke/infrastructure/base/eks-cluster-instance.yaml

# Commit and push - ArgoCD will sync automatically
git add spokes/my-spoke
git commit -m "Add my-spoke cluster"
git push
```

## Directory Structure

```
gen3-kro/
├── hub/                    # Hub cluster GitOps
│   └── argocd/
│       ├── bootstrap/      # ArgoCD bootstrap
│       ├── addons/         # Hub controllers (KRO, ACK)
│       └── fleet/          # Spoke fleet management
├── spokes/                 # Spoke cluster definitions
│   └── spoke-template/     # Template for new spokes
│       ├── infrastructure/ # KRO RGD instances
│       ├── applications/   # Workload manifests
│       └── argocd/         # ArgoCD Applications
├── shared/                 # Shared resources
│   └── kro-rgds/          # Reusable RGD library
│       └── aws/           # AWS resource graphs (EKS, VPC, IAM)
├── config/                # Configuration
│   ├── config.yaml        # Main configuration
│   ├── environments/      # Environment overrides
│   └── spokes/           # Spoke configurations
├── terraform/             # Hub infrastructure (Terragrunt)
│   ├── modules/          # Terraform modules
│   └── live/             # Environment configs
└── bootstrap/            # Scripts and utilities
    └── scripts/          # Helper scripts
```

## Documentation

- 📘 [Hub Deployment Guide](docs/deployment/hub.md)
- 📗 [Spoke Management Guide](docs/deployment/spokes.md)
- 📕 [Configuration Reference](docs/configuration.md)
- 📙 [Architecture Deep Dive](docs/architecture.md)
- 📓 [Development Guide](docs/development.md)

## Configuration

The platform uses a single source of truth: `config/config.yaml`

```yaml
hub:
  alias: "my-hub"
  aws_region: "us-east-1"
  cluster_name: "my-hub-cluster"
  kubernetes_version: "1.33"

addons:
  enable_kro: true
  enable_argocd: true
  enable_ack_iam: true
  # ... additional addons
```

## Development

### Testing

```bash
# Validate structure
./bootstrap/scripts/validate-structure.sh

# Validate Terragrunt
./bootstrap/scripts/validate-terragrunt.sh staging

# Test kustomize builds
kustomize build hub/argocd/bootstrap/base
kustomize build spokes/spoke-template/infrastructure/base
```

### Building Docker Images

```bash
# Build and push
DOCKER_PUSH=1 DOCKER_USERNAME=your-username \
  ./bootstrap/scripts/docker-build-push.sh
```

## Versioning

This project follows [Semantic Versioning](https://semver.org/):
- **v0.1.0**: Initial release with hub-spoke architecture
- Version file: `.version`

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Third-Party Licenses

This project includes code derived from third-party projects:
- Terraform AWS Modules (Apache 2.0)
- See [third-party-licenses/NOTICE.md](third-party-licenses/NOTICE.md) for full attributions

## Contributing

Contributions are welcome! Please read our contributing guidelines first.

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Submit a pull request

## Support

- 📧 Issues: [GitHub Issues](https://github.com/indiana-university/gen3-kro/issues)
- 📖 Wiki: [GitHub Wiki](https://github.com/indiana-university/gen3-kro/wiki)

## Acknowledgments

- **terraform-aws-modules** for excellent Terraform modules
- **ArgoCD** team for GitOps tooling
- **KRO** project for resource graph capabilities
- **AWS** for ACK controllers

---

**Version**: 0.1.0  
**Status**: Production Ready  
**Maintained by**: Platform Engineering Team
