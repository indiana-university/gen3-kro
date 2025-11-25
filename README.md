# Gen3-KRO

Platform for deploying Gen3 data commons infrastructure with Terragrunt-managed Terraform and GitOps (ArgoCD + KRO). A central **csoc** hub provisions cloud resources and bootstraps controllers; spoke environments consume shared KRO graphs to launch application stacks.

## Overview

`gen3-kro` provides a hub-and-spoke architecture for deploying and managing Gen3 data commons infrastructure. The platform provisions cloud resources (VPCs, Kubernetes clusters, IAM roles) via Terragrunt-managed Terraform modules, then bootstraps GitOps-driven continuous delivery using ArgoCD, cloud-specific controllers, and Kubernetes Resource Orchestrator (KRO) ResourceGraphDefinitions.

**Status**
- ✅ AWS cross-account: production-ready
- 🚧 Azure & GCP: implementation complete, validation pending
- 🚧 Cross-provider scenarios: pending

**Notes**
- KRO controller and Terragrunt are pre-1.0 but stable for production.

**Highlights**
- Multi-cloud (AWS EKS, Azure AKS, GCP GKE)
- Hub-spoke: csoc hub manages multiple spokes
- GitOps-first: ArgoCD ApplicationSets + KRO graphs
- Layered IAM policies and DRY Terragrunt catalog

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

1) Launch the VS Code devcontainer (Docker required). It ships Terraform, Terragrunt, kubectl, ArgoCD CLI, AWS/Azure/gcloud CLIs.  
2) Copy an environment and set secrets:
```bash
cd live/aws/us-east-1/<csoc_alias>
cp secrets-example.yaml secrets.yaml
```
3) Plan and apply from repo root:
```bash
./init.sh plan   # terragrunt plan --all
./init.sh apply  # terragrunt apply --all
```
4) Check access:
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
- **[Contribution Guide](CONTRIBUTING.md)**: Branching conventions, linting, PR checklist, documentation standards

## Day-2 Operations

Plan/apply from `live/<provider>/<region>/<csoc_alias>` using `terragrunt plan --all` and `terragrunt apply --all`. Sync ArgoCD addons with `argocd app sync -l argocd.argoproj.io/instance=csoc-addons`. Logs land in `outputs/logs/`. See `docs/guides/operations.md` for drift, sync, and troubleshooting.

## Contributing

We welcome contributions. Start with `CONTRIBUTING.md` and `terraform/catalog/modules/README.md`. Format with `terraform fmt -recursive terraform/` and `terragrunt hcl format` before committing.

## License

See `LICENSE` and `third-party-licenses/apache-2.0`.
