# gen3-kro

A platform for deploying Gen3 data commons that provisions cloud resources in a provider account via Terragrunt-managed Terraform modules, then bootstraps created Kubernetes clusters with cloud-specific controllers (ASO, ACKs, Config Connector) and KRO through a GitOps-driven continuous delivery (ArgoCD-managed). The csoc then uses boilerplate KRO resource graphs to deploy multiple customizable instances of the application infrastructure in the destination cloud account using their respective controllers.

## Overview

`gen3-kro` provides a hub-and-spoke architecture for deploying and managing Gen3 data commons infrastructure. The platform provisions cloud resources (VPCs, Kubernetes clusters, IAM roles) via Terragrunt-managed Terraform modules, then bootstraps GitOps-driven continuous delivery using ArgoCD, cloud-specific controllers, and Kubernetes Resource Orchestrator (KRO) ResourceGraphDefinitions.

Note: Currently, only AWS cross-account deployment has been fully tested.

**Key features:**
- **Multi-cloud support**: AWS (EKS), Azure (AKS), Google Cloud (GKE)
- **Hub-spoke topology**:  Central control plane (csoc) managing multiple spoke environments
- **GitOps workflow**:     ArgoCD ApplicationSets and KRO graphs for declarative deployments
- **IAM policy layering**: Environment-specific and default policies for fine-grained access control
- **Terragrunt-based**:    Promotes DRY principles with hierarchical configuration (catalog → combinations → units → live stacks)

## Repository Structure

```
├── terraform/               # Infrastructure as Code
│   ├── catalog/
│   │   ├── modules/         # Reusable Terraform modules (VPC, EKS, AKS, GKE, IAM, ArgoCD)
│   │   └── combinations/    # Provider-specific compositions (csoc, spoke)
│   └── units/               # Terragrunt unit definitions (csoc, spokes)
├── argocd/                  # GitOps manifests
│   ├── bootstrap/           # App-of-apps ApplicationSets (csoc-addons, spoke-addons, graphs)
│   ├── addons/              # Addon catalogs and values (KRO, ACK controllers)
│   ├── graphs/              # KRO ResourceGraphDefinitions by cloud provider
│   └── spokes/              # Spoke-specific overlays and application definitions
├── iam/                     # IAM policy definitions
│   ├── aws/                 # AWS pod identity policies
│   ├── azure/               # Azure managed identity policies
│   └── gcp/                 # GCP workload identity policies
├── live/                    # Environment configurations
│   └── aws/us-east-1/gen3-kro-dev/   # Example environment
│       ├── terragrunt.stack.hcl      # Stack definition in Terragrunt HCL format
│       ├── credentials/              # Cloud provider credentials (gitignored)
│       └── secrets.yaml              # Sensitive configuration (gitignored)
├── scripts/                 # Automation utilities
│   ├── connect-cluster.sh   # Configure kubectl/ArgoCD CLI access
│   ├── docker-build-push.sh # Build and publish container images
│   └── version-bump.sh      # Semantic versioning helper
├── outputs/                 # Generated outputs and logs
│   └── logs/                # Terragrunt and script execution logs
├── .devcontainer/           # VS Code dev container definitions
├── docs/                    # User guides
└── init.sh                  # Bootstrap wrapper for Terragrunt operations
```

## Quick Start

### 1. Launch Development Environment

Open this repository in a VS Code dev container (requires Docker):

```bash
# VS Code will detect .devcontainer/devcontainer.json
# Select "Reopen in Container" when prompted

# Or use Docker CLI directly with the root Dockerfile:
docker build -t gen3-kro-dev .
docker run -it --rm -v $(pwd):/workspace -w /workspace gen3-kro-dev bash
```

The Docker container includes all required tools: Terragrunt, Terraform, kubectl, ArgoCD CLI, AWS CLI, Azure CLI, gcloud.

### 2. Configure Environment

Navigate to your environment directory (or copy the example):

```bash
cd live/aws/us-east-1/<csoc_alias>
cp secrets-example.yaml secrets.yaml
# Edit secrets.yaml with your cloud credentials and configuration
```

See [`live/README.md`](live/README.md) for secrets schema and [`docs/guides/setup.md`](docs/guides/setup.md) for detailed first-time setup.

### 3. Deploy Infrastructure

Run the bootstrap script from the repository root:

```bash
./init.sh plan   # Preview changes (runs terragrunt plan --all)
./init.sh apply  # Deploy csoc hub and spokes (runs terragrunt apply --all)
```

This will:
1. Provision cloud resources (VPC, cluster, IAM roles) using the Terraform catalog
2. Install ArgoCD on the hub cluster
3. Deploy bootstrap ApplicationSets that sync addons and spoke configurations from the GitOps repository
4. Automatically configure kubectl and ArgoCD CLI access

### 4. Verify Cluster Access

After deployment completes, verify connectivity:

```bash
kubectl get nodes
argocd app list
```

## Documentation

- **[Terraform Catalog](terraform/README.md)**: Module layering, supported providers, testing workflows
- **[ArgoCD GitOps](argocd/README.md)**: ApplicationSet hierarchy, sync strategy, secret management
- **[IAM Policies](iam/README.md)**: Policy organization, environment overrides, controller mappings
- **[Live Environments](live/README.md)**: Stack configuration, secrets handling, deployment checklists
- **[Development Container](.devcontainer/README.md)**: Devcontainer setup, VS Code extensions, environment variables
- **[Automation Scripts](scripts/README.md)**: Script reference, inputs, destructive operations

### User Guides

- **[Setup Guide](docs/guides/setup.md)**: Step-by-step onboarding for new contributors
- **[Customization Guide](docs/guides/customization.md)**: Overriding modules, adjusting IAM policies, extending KRO graphs
- **[Operations Guide](docs/guides/operations.md)**: Day-2 operations (planning, applying, syncing, troubleshooting)
- **[Contribution Guide](docs/guides/contributing.md)**: Branching conventions, linting, PR checklist, documentation standards

## Day-2 Operations

**Plan changes:**
```bash
cd live/<provider>/<region>/<csoc_alias>
terragrunt plan --all
```

**Apply updates:**
```bash
terragrunt apply --all
```

**Sync ArgoCD applications:**
```bash
argocd app sync -l argocd.argoproj.io/instance=csoc-addons
```

**Review logs:**
```bash
./outputs/logs/terragrunt-*.log
./outputs/logs/connect-cluster-*.log
```

See [`docs/operations.md`](docs/guides/operations.md) for troubleshooting drift, rotating credentials, and managing spoke environments.

## Contributing

We welcome contributions! Please review:
- [Contribution guidelines](docs/guides/contributing.md) for branching conventions and PR requirements
- [Terraform module standards](terraform/catalog/modules/README.md) for authoring new modules

Lint and format before committing:
```bash
terraform fmt -recursive terraform/
terragrunt hcl format
```

## License

See [LICENSE](LICENSE) for details.
See [Apache 2.0 License](third-party-licenses/apache-2.0) for licensing information.

---
**Last updated:** 2025-10-28
