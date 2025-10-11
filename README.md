# Gen3 KRO - Kubernetes Resource Orchestration

Gen3 KRO is an enterprise-grade GitOps platform for managing AWS Controllers for Kubernetes (ACK) and Kubernetes infrastructure across hub-and-spoke cluster architectures using ArgoCD and Terraform.

## Overview

This project implements a scalable multi-cluster Kubernetes management platform designed for Gen3 data commons infrastructure. It leverages:

- **ArgoCD** for GitOps-based continuous delivery
- **AWS Controllers for Kubernetes (ACK)** for managing AWS resources natively in Kubernetes
- **Terraform/Terragrunt** for infrastructure provisioning
- **Hub-and-Spoke Architecture** for centralized control and distributed workloads
- **Kro (Kubernetes Resource Orchestrator)** for advanced resource management

## Architecture

The platform follows a hub-and-spoke model:

- **Hub Cluster**: Central control plane running ArgoCD and managing ACK controllers
- **Spoke Clusters**: Distributed workload clusters managed by the hub

### Key Components

1. **ACK Controllers**: Manage AWS resources (IAM, EKS, EC2, EFS, RDS, S3, etc.) as Kubernetes custom resources
2. **ArgoCD ApplicationSets**: Automated application deployment across multiple clusters
3. **Terraform Modules**: Infrastructure provisioning for EKS clusters and IAM roles
4. **KRO Resource Graph Definitions**: Advanced orchestration of complex resource dependencies

## Project Structure

```
.
├── argocd/                    # ArgoCD manifests and configurations
│   ├── hub/                   # Hub cluster configurations
│   │   ├── bootstrap/         # Initial cluster setup
│   │   ├── charts/            # Helm charts for addons
│   │   ├── shared/            # Shared ApplicationSets
│   │   │   ├── applicationsets/
│   │   │   │   └── ack-controllers.yaml  # ACK controllers deployment
│   │   │   └── kro-rgds/      # KRO Resource Graph Definitions
│   │   └── values/            # Configuration values
│   │       ├── ack-defaults.yaml
│   │       └── ack-overrides/ # Per-controller configurations
│   └── spokes/                # Spoke cluster configurations
├── bootstrap/                 # Bootstrap scripts and utilities
│   ├── terragrunt-wrapper.sh # Terragrunt execution wrapper
│   └── scripts/               # Helper scripts
├── config/                    # Environment configurations
│   ├── config.yaml            # Main configuration
│   └── environments/          # Environment-specific configs
├── terraform/                 # Infrastructure as Code
│   ├── modules/
│   │   ├── argocd-bootstrap/  # ArgoCD installation
│   │   ├── eks-hub/           # Hub cluster provisioning
│   │   ├── iam-access/        # IAM roles and policies
│   │   └── root/              # Root module
│   └── live/                  # Environment-specific configs
└── docs/                      # Documentation and diagrams
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl (1.28+)
- Terraform (1.5+)
- Terragrunt (0.50+)
- Docker (for dev container)
- Git

## Getting Started

### 1. Environment Setup

Configure your environment in `config/environments/<env>.yaml`:

```yaml
environment: staging
aws_account_id: "123456789012"
aws_region: "us-east-1"
cluster_name: "gen3-kro-hub-staging"
```

### 2. Deploy Infrastructure

Use the Terragrunt wrapper to provision infrastructure:

```bash
# Deploy staging environment
./bootstrap/terragrunt-wrapper.sh staging apply

# Deploy production environment
./bootstrap/terragrunt-wrapper.sh prod apply
```

### 3. Connect to Cluster

```bash
# Connect to the hub cluster
./bootstrap/scripts/connect-cluster.sh staging
```

### 4. Verify ACK Controllers

```bash
# Check deployed ACK applications
kubectl get applications -n argocd | grep ack

# Verify controller pods
kubectl get pods -n ack-system
```

## ACK Controllers

The platform deploys the following AWS Controllers for Kubernetes:

| Controller | Purpose | Namespace | Status |
|------------|---------|-----------|--------|
| IAM | Manage IAM roles, policies, and users | ack-system | ✅ Deployed |
| EKS | Manage EKS clusters and node groups | ack-system | ✅ Deployed |
| EC2 | Manage EC2 instances and networking | ack-system | ✅ Deployed |
| EFS | Manage Elastic File Systems | ack-system | ✅ Deployed |
| RDS | Manage RDS databases | ack-system | Configured |
| S3 | Manage S3 buckets | ack-system | Configured |
| Route53 | Manage DNS records | ack-system | Configured |
| Secrets Manager | Manage secrets | ack-system | Configured |
| CloudWatch Logs | Manage log groups | ack-system | Configured |
| SNS | Manage notifications | ack-system | Configured |
| SQS | Manage message queues | ack-system | Configured |
| KMS | Manage encryption keys | ack-system | Configured |
| WAFv2 | Manage web application firewall | ack-system | Configured |
| OpenSearch | Manage OpenSearch domains | ack-system | Configured |
| CloudTrail | Manage audit trails | ack-system | Configured |

### ACK Configuration

Controllers are configured via the unified ApplicationSet pattern (`argocd/hub/shared/applicationsets/ack-controllers.yaml`):

- **Single ApplicationSet** manages all controllers
- **Matrix generator** combines controller definitions with cluster selectors
- **Per-cluster enablement** via cluster labels (`enable_ack_<controller>=true`)
- **Role-based access** with IRSA (IAM Roles for Service Accounts)
- **Customizable values** in `argocd/hub/values/ack-overrides/`

## Configuration Management

### Main Configuration

Edit `config/config.yaml` to customize:

- Hub cluster settings
- ACK controller list
- GitOps repository settings
- AWS resource naming
- Terraform state configuration

### ACK Controller Overrides

Per-controller customization in `argocd/hub/values/ack-overrides/<controller>.yaml`:

```yaml
aws:
  region: us-east-1
resources:
  limits:
    cpu: 200m
    memory: 256Mi
```

## ArgoCD Access

Access the ArgoCD UI:

```bash
# Port-forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Navigate to: `https://localhost:8080`

## Development

### Dev Container

This repository includes a VS Code dev container with all required tools pre-installed:

- Git (latest)
- Docker CLI
- kubectl
- AWS CLI
- Terraform/Terragrunt

### Git Hooks

Install git hooks for validation:

```bash
./bootstrap/scripts/install-git-hooks.sh
```

### Scripts

| Script | Purpose |
|--------|---------|
| `terragrunt-wrapper.sh` | Execute Terragrunt commands |
| `connect-cluster.sh` | Configure kubectl for cluster access |
| `validate-terragrunt.sh` | Validate Terragrunt configurations |
| `version-bump.sh` | Bump version and create releases |

## Troubleshooting

### ACK Controller Issues

```bash
# Check controller logs
kubectl logs -n ack-system -l app.kubernetes.io/name=<controller>-chart

# Verify IRSA configuration
kubectl describe sa -n ack-system ack-<controller>-controller

# Check ArgoCD sync status
kubectl get applications -n argocd <cluster>-ack-<controller> -o yaml
```

### Terraform State Issues

```bash
# Validate configuration
./bootstrap/terragrunt-wrapper.sh <env> validate

# Check state
./bootstrap/terragrunt-wrapper.sh <env> show
```

## Security

- **IRSA**: All ACK controllers use IAM Roles for Service Accounts
- **Least Privilege**: Controllers have minimal IAM permissions
- **GitOps**: All changes tracked in Git
- **Secrets**: Stored in AWS Secrets Manager, not in Git
- **Network Policies**: Restrict pod-to-pod communication

## Contributing

1. Create a feature branch from `staging`
2. Make changes following GitOps principles
3. Test in staging environment
4. Submit pull request with detailed description
5. Merge to `staging`, then promote to `main` for production

## License

See [LICENSE](../LICENSE) file for details.

## Support

For issues and questions:
- Check existing documentation in `docs/`
- Review ArgoCD application status
- Examine pod logs for detailed errors
- Contact the platform team

## Release History

- **v0.2.0** (October 2025): ACK controllers deployed to hub cluster with ApplicationSet pattern
- **v0.1.0** (October 2025): Initial infrastructure setup with Terraform and ArgoCD

## Additional Resources

- [AWS Controllers for Kubernetes Documentation](https://aws-controllers-k8s.github.io/community/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/)
- [Architecture Diagram](kro-hub%20architectural%20diagram.png)
