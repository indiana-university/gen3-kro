# Gen3 KRO - Kubernetes Resource Orchestration Platform# Gen3 KRO - Kubernetes Resource Orchestration



[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)Gen3 KRO is an enterprise-grade GitOps platform for managing AWS Controllers for Kubernetes (ACK) and Kubernetes infrastructure across hub-and-spoke cluster architectures using ArgoCD and Terraform.

[![Docker](https://img.shields.io/badge/Docker-Hub-blue)](https://hub.docker.com/r/indiana-university/gen3-kro)

[![Terraform](https://img.shields.io/badge/Terraform-1.5%2B-purple)](https://www.terraform.io/)## Overview

[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28%2B-blue)](https://kubernetes.io/)

This project implements a scalable multi-cluster Kubernetes management platform designed for Gen3 data commons infrastructure. It leverages:

**Gen3 KRO** is an enterprise-grade GitOps platform for managing multi-cluster Kubernetes infrastructure using AWS Controllers for Kubernetes (ACK), ArgoCD, and Terraform. Designed for Gen3 data commons infrastructure, it provides centralized control and automated orchestration across hub-and-spoke cluster architectures.

- **ArgoCD** for GitOps-based continuous delivery

---- **AWS Controllers for Kubernetes (ACK)** for managing AWS resources natively in Kubernetes

- **Terraform/Terragrunt** for infrastructure provisioning

## 🎯 Overview- **Hub-and-Spoke Architecture** for centralized control and distributed workloads

- **Kro (Kubernetes Resource Orchestrator)** for advanced resource management

Gen3 KRO implements a scalable, production-ready platform that:

## Architecture

- **Manages AWS resources as Kubernetes manifests** using ACK controllers

- **Automates infrastructure provisioning** with KRO (Kubernetes Resource Orchestrator) Resource Graph DefinitionsThe platform follows a hub-and-spoke model:

- **Deploys applications declaratively** via ArgoCD ApplicationSets

- **Scales across multiple clusters** with hub-and-spoke architecture- **Hub Cluster**: Central control plane running ArgoCD and managing ACK controllers

- **Enforces GitOps workflows** for infrastructure-as-code and application deployment- **Spoke Clusters**: Distributed workload clusters managed by the hub



### Key Use Cases### Key Components



- **Multi-cluster management**: Centralized control plane managing distributed workload clusters1. **ACK Controllers**: Manage AWS resources (IAM, EKS, EC2, EFS, RDS, S3, etc.) as Kubernetes custom resources

- **Infrastructure automation**: Declarative AWS resource provisioning (VPC, EKS, IAM, RDS, S3, etc.)2. **ArgoCD ApplicationSets**: Automated application deployment across multiple clusters

- **Gen3 data commons**: Automated deployment of Gen3 workloads across multiple environments3. **Terraform Modules**: Infrastructure provisioning for EKS clusters and IAM roles

- **Self-service infrastructure**: Developer-friendly Kubernetes-native AWS resource management4. **KRO Resource Graph Definitions**: Advanced orchestration of complex resource dependencies



---## Project Structure



## 🏗️ Architecture```

.

### Hub-and-Spoke Model├── argocd/                    # ArgoCD manifests and configurations

│   ├── hub/                   # Hub cluster configurations

```│   │   ├── bootstrap/         # Initial cluster setup

┌─────────────────────────────────────────────────────────────┐│   │   ├── charts/            # Helm charts for addons

│                        Hub Cluster                          ││   │   ├── shared/            # Shared ApplicationSets

│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  ││   │   │   ├── applicationsets/

│  │   ArgoCD     │  │ KRO Engine   │  │  ACK Controllers │  ││   │   │   │   └── ack-controllers.yaml  # ACK controllers deployment

│  │ (Control)    │  │ (RGDs)       │  │  (Hub-specific)  │  ││   │   │   └── kro-rgds/      # KRO Resource Graph Definitions

│  └──────────────┘  └──────────────┘  └──────────────────┘  ││   │   └── values/            # Configuration values

└─────────────────────────────────────────────────────────────┘│   │       ├── ack-defaults.yaml

                              ││   │       └── ack-overrides/ # Per-controller configurations

              ┌───────────────┼───────────────┐│   └── spokes/                # Spoke cluster configurations

              │               │               │├── bootstrap/                 # Bootstrap scripts and utilities

              ▼               ▼               ▼│   ├── terragrunt-wrapper.sh # Terragrunt execution wrapper

    ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐│   └── scripts/               # Helper scripts

    │  Spoke Cluster  │ │  Spoke Cluster  │ │  Spoke Cluster  │├── config/                    # Configuration files

    │   (Workloads)   │ │   (Workloads)   │ │   (Workloads)   ││   ├── base.yaml              # Base configuration

    │  ACK Controllers│ │  ACK Controllers│ │  ACK Controllers││   └── config.yaml            # Main configuration

    └─────────────────┘ └─────────────────┘ └─────────────────┘├── terraform/                 # Infrastructure as Code

```│   ├── modules/

│   │   ├── argocd-bootstrap/  # ArgoCD installation

### Components│   │   ├── eks-hub/           # Hub cluster provisioning

│   │   ├── iam-spoke/        # IAM spoke roles and policies

| Component | Purpose | Location |│   │   └── root/              # Root module

|-----------|---------|----------|│   └── live/                  # Terragrunt configuration

| **Hub Cluster** | Central control plane running ArgoCD, KRO controller, and infrastructure management | AWS EKS |└── docs/                      # Documentation and diagrams

| **Spoke Clusters** | Distributed workload clusters running Gen3 applications and workload-specific controllers | AWS EKS |```

| **ACK Controllers** | Kubernetes operators managing AWS resources (15+ services supported) | Hub + Spokes |

| **KRO RGDs** | Resource Graph Definitions orchestrating complex infrastructure dependencies | Hub |## Prerequisites

| **ArgoCD ApplicationSets** | Automated multi-cluster application deployment with wave-based ordering | Hub |

| **Terraform Modules** | Infrastructure provisioning for initial EKS clusters, IAM roles, and bootstrap | IaC |- AWS CLI configured with appropriate credentials

- kubectl (1.28+)

### Deployment Waves- Terraform (1.5+)

- Terragrunt (0.50+)

The platform uses a **4-wave deployment strategy** for proper dependency management:- Docker (for dev container)

- Git

```

Wave 0: Platform Addons (ACK, KRO, External Secrets, Kyverno)## Getting Started

   ↓

Wave 1: Resource Graph Definitions (VPC, EKS, IAM templates)### 1. Configuration

   ↓

Wave 2: Graph Instances (Spoke cluster provisioning)Configure your cluster in `config/base.yaml`:

   ↓

Wave 3: Gen3 Instances (Application workloads)```yaml

```hub:

  cluster_name: "gen3-kro-hub"

---  aws_region: "us-east-1"

  aws_profile: "default"

## 🚀 Quick Start```



### Prerequisites### 2. Deploy Infrastructure



| Tool | Version | Purpose |Use the Terragrunt wrapper to provision infrastructure:

|------|---------|---------|

| AWS CLI | 2.x | AWS API interaction |```bash

| Terraform | 1.5+ | Infrastructure provisioning |# Deploy infrastructure

| Terragrunt | 0.50+ | Terraform orchestration |./bootstrap/terragrunt-wrapper.sh apply

| kubectl | 1.28+ | Kubernetes CLI |```

| Docker | 20.x+ | Dev container |

| Git | 2.x | Version control |### 3. Connect to Cluster



### 1. Configure Environment```bash

# Connect to the hub cluster

Edit `config/config.yaml` with your environment details:

```bash
./scripts/connect-cluster.sh

```

```yaml

hub:### 4. Verify ACK Controllers

  cluster_name: "gen3-kro-hub"

  aws_region: "us-east-1"```bash

  aws_profile: "your-profile"# Check deployed ACK applications

  kubernetes_version: "1.33"kubectl get applications -n argocd | grep ack



ack:# Verify controller pods

  controllers:kubectl get pods -n ack-system

    - iam```

    - eks

    - ec2## ACK Controllers

    - efs

    - rdsThe platform deploys the following AWS Controllers for Kubernetes:

    - s3

    # ... more controllers| Controller | Purpose | Namespace | Status |

```|------------|---------|-----------|--------|

| IAM | Manage IAM roles, policies, and users | ack-system | ✅ Deployed |

### 2. Deploy Hub Infrastructure| EKS | Manage EKS clusters and node groups | ack-system | ✅ Deployed |

| EC2 | Manage EC2 instances and networking | ack-system | ✅ Deployed |

Use the Terragrunt wrapper to provision the hub cluster:| EFS | Manage Elastic File Systems | ack-system | ✅ Deployed |

| RDS | Manage RDS databases | ack-system | Configured |

```bash| S3 | Manage S3 buckets | ack-system | Configured |

# Initialize and apply infrastructure| Route53 | Manage DNS records | ack-system | Configured |

./bootstrap/terragrunt-wrapper.sh apply| Secrets Manager | Manage secrets | ack-system | Configured |

| CloudWatch Logs | Manage log groups | ack-system | Configured |

# Monitor deployment (takes ~20-30 minutes)| SNS | Manage notifications | ack-system | Configured |

watch kubectl get pods -n argocd| SQS | Manage message queues | ack-system | Configured |

```| KMS | Manage encryption keys | ack-system | Configured |

| WAFv2 | Manage web application firewall | ack-system | Configured |

### 3. Connect to Hub Cluster| OpenSearch | Manage OpenSearch domains | ack-system | Configured |

| CloudTrail | Manage audit trails | ack-system | Configured |

```bash

# Configure kubectl context### ACK Configuration

./scripts/connect-cluster.sh

Controllers are configured via the unified ApplicationSet pattern (`argocd/bootstrap/hub-addons.yaml`):

# Verify connection

kubectl cluster-info- **Single ApplicationSet** manages all controllers

kubectl get nodes- **Matrix generator** combines controller definitions with cluster selectors

```- **Per-cluster enablement** via cluster labels (`enable_ack_<controller>=true`)

- **Role-based access** with IRSA (IAM Roles for Service Accounts)

### 4. Verify ArgoCD Deployment- **Customizable values** in `argocd/hub/values/ack-overrides/`



```bash## Configuration Management

# Check ArgoCD ApplicationSets

kubectl get applicationsets -n argocd### Main Configuration



# Expected output:Edit `config/config.yaml` to customize:

# NAME                AGE

# bootstrap           5m- Hub cluster settings

# hub-addons          5m- ACK controller list

# graphs              5m- GitOps repository settings

# graph-instances     5m- AWS resource naming

- Terraform state configuration

# Access ArgoCD UI

kubectl port-forward -n argocd svc/argocd-server 8080:443### ACK Controller Overrides

# Visit: https://localhost:8080

```Per-controller customization in `argocd/hub/values/ack-overrides/<controller>.yaml`:



### 5. Verify ACK Controllers```yaml

aws:

```bash  region: us-east-1

# Check ACK controller deploymentsresources:

kubectl get pods -n ack-system  limits:

    cpu: 200m

# Verify IRSA (IAM Roles for Service Accounts)    memory: 256Mi

kubectl describe sa -n ack-system ack-iam-controller```



# Test ACK functionality (create IAM role)## ArgoCD Access

cat <<EOF | kubectl apply -f -

apiVersion: iam.services.k8s.aws/v1alpha1Access the ArgoCD UI:

kind: Role

metadata:```bash

  name: test-role# Port-forward to ArgoCD server

spec:kubectl port-forward svc/argocd-server -n argocd 8080:443

  name: test-role-from-ack

  assumeRolePolicyDocument: |# Get admin password

    {kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

      "Version": "2012-10-17",```

      "Statement": [{

        "Effect": "Allow",Navigate to: `https://localhost:8080`

        "Principal": {"Service": "ec2.amazonaws.com"},

        "Action": "sts:AssumeRole"## Development

      }]

    }### Dev Container

EOF

This repository includes a VS Code dev container with all required tools pre-installed:

# Verify role created in AWS

aws iam get-role --role-name test-role-from-ack- Git (latest)

```- Docker CLI

- kubectl

---- AWS CLI

- Terraform/Terragrunt

## 📁 Project Structure

### Git Hooks

```

gen3-kro/Install git hooks for validation:

├── argocd/                          # ArgoCD manifests and GitOps config

│   ├── bootstrap/                   # Bootstrap ApplicationSets (deployed by Terraform)```bash

│   │   ├── hub-addons.yaml          # Wave 0: Platform addons (ACK, KRO)./scripts/install-git-hooks.sh

│   │   ├── spoke-addons.yaml        # Wave 0: Spoke-specific addons```

│   │   ├── graphs.yaml              # Wave 1: RGD deployment

│   │   ├── graph-instances.yaml     # Wave 2: Infrastructure instances### Scripts

│   │   └── gen3-instances.yaml      # Wave 3: Workload deployment

│   ├── hub/                         # Hub cluster configurations| Script | Purpose |

│   │   ├── charts/                  # Helm charts for addons|--------|---------|

│   │   ├── shared/                  | `terragrunt-wrapper.sh` | Execute Terragrunt commands |

│   │   │   ├── applicationsets/     # ACK controllers ApplicationSet| `connect-cluster.sh` | Configure kubectl for cluster access |

│   │   │   └── kro-rgds/            # Resource Graph Definitions| `validate-terragrunt.sh` | Validate Terragrunt configurations |

│   │   │       └── aws/             # AWS infrastructure RGDs| `version-bump.sh` | Bump version and create releases |

│   │   │           ├── vpc-network-rgd.yaml

│   │   │           ├── eks-basic-rgd.yaml## Troubleshooting

│   │   │           └── eks-cluster-rgd.yaml

│   │   └── values/                  # Configuration values### ACK Controller Issues

│   │       ├── ack-defaults.yaml    # Default ACK controller config

│   │       └── ack-overrides/       # Per-controller overrides```bash

│   ├── spokes/                      # Spoke cluster configurations# Check controller logs

│   │   └── spoke1/                  # Example spoke configurationkubectl logs -n ack-system -l app.kubernetes.io/name=<controller>-chart

│   │       ├── addons/              # Spoke-specific addon config

│   │       ├── infrastructure/      # Spoke cluster definition# Verify IRSA configuration

│   │       └── sample.gen3.url.org/ # Gen3 workload appskubectl describe sa -n ack-system ack-<controller>-controller

│   └── plans/                       # Deployment phase documentation

│       ├── Phase0.md                # Foundation setup# Check ArgoCD sync status

│       ├── Phase1.md                # Hub bootstrapkubectl get applications -n argocd <cluster>-ack-<controller> -o yaml

│       ├── Phase2.md                # Platform addons```

│       ├── Phase3.md                # Resource graphs

│       ├── Phase4.md                # Spoke infrastructure### Terraform State Issues

│       └── Phase5.md                # Workload deployment

├── bootstrap/                       # Bootstrap scripts```bash

│   ├── terragrunt-wrapper.sh        # Terragrunt execution wrapper# Validate configuration

│   └── scripts/                     ./bootstrap/terragrunt-wrapper.sh <env> validate

│       ├── connect-cluster.sh       # Cluster connection helper

│       ├── docker-build-push.sh     # Container image builder# Check state

│       └── version-bump.sh          # Semantic versioning./bootstrap/terragrunt-wrapper.sh <env> show

├── config/                          # Configuration files```

│   ├── base.yaml                    # Base configuration template

│   └── config.yaml                  # Main configuration (customize)## Security

├── terraform/                       # Infrastructure as Code

│   ├── modules/                     - **IRSA**: All ACK controllers use IAM Roles for Service Accounts

│   │   ├── argocd-bootstrap/        # ArgoCD installation module- **Least Privilege**: Controllers have minimal IAM permissions

│   │   ├── eks-hub/                 # Hub cluster provisioning- **GitOps**: All changes tracked in Git

│   │   ├── iam-spoke/              # IAM roles for ACK controllers- **Secrets**: Stored in AWS Secrets Manager, not in Git

│   │   └── root/                    # Root orchestration module- **Network Policies**: Restrict pod-to-pod communication

│   └── live/                        # Terragrunt live configuration

│       └── terragrunt.hcl           # Terragrunt config## CI/CD Pipeline

├── outputs/                         # Generated outputs and logs

├── docs/                            # Additional documentation### Automated Versioning

├── Dockerfile                       # Multi-stage dev container

├── Proposal.md                      # Comprehensive architecture docThe project uses **fully automated semantic versioning** via GitHub Actions. No manual version file updates needed for patch releases!

└── README.md                        # This file

```**Status:** ✅ Tested and working on `jimi-container`, `main`, and `staging` branches (October 2025)



---**How it works:**

1. **Every push to monitored branches**: The CI automatically bumps the patch version (e.g., 0.3.1 → 0.3.2)

## 🔧 Key Features2. **Version file auto-updates**: The `.version` file is updated and committed by the CI

3. **Git tags created**: New version tags (e.g., `v0.3.2`) are automatically created and pushed

### 1. AWS Controllers for Kubernetes (ACK)4. **Docker images published**: Images are tagged with the new version



Manage 15+ AWS services natively through Kubernetes:**For major/minor version changes only:**

- Update `.version` file manually (e.g., `echo "0.4.0" > .version`)

**Supported Controllers:**- Commit and push to your branch

- **iam**: IAM roles, policies, users, groups- CI detects the change and creates the appropriate tag

- **eks**: EKS clusters, node groups, addons

- **ec2**: Instances, security groups, VPCs, subnets**Version bump logic:**

- **efs**: Elastic File Systems, mount targets- If `.version` matches latest git tag → **auto-bump patch** (0.3.1 → 0.3.2)

- **rds**: RDS databases, clusters, snapshots- If `.version` has new major/minor → **use file version** (0.3.x → 0.4.0)

- **s3**: S3 buckets, policies, lifecycle rules- Tag already exists → **error** (prevents duplicate releases)

- **route53**: DNS zones, records, health checks

- **kms**: KMS keys, aliases, grants### Docker Image Build

- **secretsmanager**: Secrets, versions, rotation

- **cloudtrail**: Trails, event selectorsEvery push to `main`, `staging`, or tag triggers:

- **cloudwatchlogs**: Log groups, streams, metric filters1. Version auto-increment (if applicable)

- **opensearchservice**: OpenSearch domains, clusters2. Docker image build from `.devcontainer/Dockerfile`

- **sns**: SNS topics, subscriptions3. Multi-tag push to Docker Hub:

- **sqs**: SQS queues, policies   - `<repo>:v<version>-<date>-g<sha>` (immutable)

- **wafv2**: WAF web ACLs, rules, IP sets   - `<repo>:v<version>` (mutable)

   - `<repo>:latest` (main branch only)

**Example Usage:**

### Version Management Script

```yaml

# Create an RDS instance using ACKLocated at `.github/workflows/version-bump.sh`, this script:

apiVersion: rds.services.k8s.aws/v1alpha1- **Auto-detects** if version bump is needed

kind: DBInstance- Compares `.version` file with latest git tag

metadata:- **Auto-bumps patch** if major/minor unchanged and versions match

  name: gen3-postgres- Creates annotated git tags automatically

spec:- Outputs version for CI/CD consumption

  dbInstanceIdentifier: gen3-postgres-prod- **Fails fast** if tag already exists (prevents duplicates)

  dbInstanceClass: db.r5.large

  engine: postgres**You don't need to run this manually** - the CI handles it automatically!

  engineVersion: "15.4"

  masterUsername: admin**For testing purposes only:**

  masterUserPassword:```bash

    namespace: default# Test the version bump script locally

    name: db-password./.github/workflows/version-bump.sh

    key: password

  allocatedStorage: 100# Check results

  storageType: gp3cat .version

  vpcSecurityGroupIDs:git tag --list | sort -V | tail -3

    - sg-123456789```

  dbSubnetGroupName: gen3-db-subnet-group

```**Manual major/minor version bump example:**

```bash

### 2. KRO Resource Graph Definitions (RGDs)# Update .version file

echo "0.4.0" > .version

Orchestrate complex infrastructure with declarative graphs:

# Run version script manually

**Available RGDs:**./.github/workflows/version-bump.sh

- **vpc-network-rgd**: VPC, subnets, NAT gateways, route tables

- **eks-basic-rgd**: Simplified EKS cluster provisioning# Push changes

- **eks-cluster-rgd**: Full-featured EKS with node groups, addons, securitygit add .version

git commit -m "chore: bump to v0.4.0"

**Example Instance:**git push origin main --tags

```

```yaml

apiVersion: v1alpha1## Contributing

kind: EksCluster

metadata:1. Create a feature branch from `staging`

  name: spoke1-cluster2. Make changes following GitOps principles

spec:3. Test in staging environment

  name: spoke14. Submit pull request with detailed description

  region: us-west-25. Merge to `staging`, then promote to `main` for production

  k8sVersion: "1.33"

  accountId: "987654321098"## License

  vpc:

    vpcCidr: "10.1.0.0/16"See [LICENSE](../LICENSE) file for details.

    publicSubnet1Cidr: "10.1.1.0/24"

    privateSubnet1Cidr: "10.1.11.0/24"## Support

```

For issues and questions:

### 3. ApplicationSet-Based Deployment- Check existing documentation in `docs/`

- Review ArgoCD application status

Automated multi-cluster application deployment:- Examine pod logs for detailed errors

- Contact the platform team

**Matrix Generators:**

```yaml## Release History

generators:

  - matrix:- **v0.3.2** (October 2025): CI/CD pipeline fixes - automated version bumping and tagging

      generators:- **v0.3.1** (October 2025): ArgoCD architecture refactoring with new bootstrap pattern

        - git:- **v0.3.0** (October 2025): Staging ACK deployment with unified ApplicationSet pattern

            repoURL: https://github.com/indiana-university/gen3-kro- **v0.2.0** (October 2025): ACK controllers deployed to hub cluster with ApplicationSet pattern

            directories:- **v0.1.0** (October 2025): Initial infrastructure setup with Terraform and ArgoCD

              - path: argocd/spokes/*

        - clusters:## Additional Resources

            selector:

              matchLabels:- [AWS Controllers for Kubernetes Documentation](https://aws-controllers-k8s.github.io/community/)

                fleet_member: spoke- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

```- [Terragrunt Documentation](https://terragrunt.gruntwork.io/)

- [Architecture Diagram](kro-hub%20architectural%20diagram.png)

**Per-Cluster Configuration:**
- Cluster labels control addon enablement
- Per-controller IAM role configuration
- Environment-specific values and secrets

### 4. Phased Deployment Strategy

**Phase 0: Foundation Setup**
- Repository structure finalization
- IAM role creation (30+ roles for ACK controllers)
- Terraform configuration
- Duration: 2-3 days

**Phase 1: Hub Bootstrap**
- Hub cluster provisioning
- ArgoCD installation
- Bootstrap ApplicationSet deployment
- Duration: 1-2 days

**Phase 2: Platform Addons**
- KRO controller deployment
- ACK controller deployment (15+ controllers)
- Platform components (external-secrets, kyverno)
- Duration: 2-3 days

**Phase 3: Resource Graphs**
- RGD deployment to hub cluster
- KRO controller readiness validation
- Duration: 1 day

**Phase 4: Spoke Infrastructure**
- First spoke cluster provisioning
- Spoke registration with hub ArgoCD
- Spoke addon deployment
- Duration: 3-5 days

**Phase 5: Workload Deployment**
- Gen3 application deployment
- Health checks and validation
- Duration: 2-3 days

**Total Duration**: 11-17 days (conservative with buffer)

---

## 🔐 Security & IAM

### IAM Roles for Service Accounts (IRSA)

Each ACK controller uses dedicated IAM roles with least-privilege policies:

**Hub IAM Roles:**
- `gen3-kro-hub-ack-iam-role` - IAM resource management
- `gen3-kro-hub-ack-eks-role` - EKS cluster management
- `gen3-kro-hub-ack-ec2-role` - EC2 resource management
- ... (15 total controllers)

**Spoke IAM Roles:**
- Separate roles per spoke cluster
- Cross-account trust relationships
- Environment-specific policies

**Configuration:**

```yaml
# argocd/hub/values/ack-defaults.yaml
iam:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/gen3-kro-hub-ack-iam-role
```

---

## 📊 Monitoring & Operations

### ArgoCD Health Checks

```bash
# Check ApplicationSet status
kubectl get applicationsets -n argocd

# Check Application health
kubectl get applications -n argocd

# View sync status
argocd app list

# Check sync waves
kubectl get applications -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.argocd\.argoproj\.io/sync-wave}{"\n"}{end}'
```

### ACK Controller Monitoring

```bash
# Check controller pods
kubectl get pods -n ack-system

# View controller logs
kubectl logs -n ack-system deployment/ack-iam-controller

# Check reconciliation status
kubectl get iamroles -A

# View controller metrics
kubectl top pods -n ack-system
```

### KRO Monitoring

```bash
# Check KRO controller
kubectl get pods -n kro-system

# List Resource Graph Definitions
kubectl get resourcegraphdefinitions

# List instances
kubectl get ekscluster -A

# View instance status
kubectl describe ekscluster spoke1-cluster
```

---

## 🛠️ Development

### Dev Container

This project includes a complete dev container with all tools pre-installed:

```bash
# Start dev container (VS Code)
# 1. Open folder in VS Code
# 2. Press F1 → "Dev Containers: Reopen in Container"

# Included tools:
# - Terraform 1.5.7
# - Terragrunt 0.55.1
# - kubectl 1.31.0
# - Helm 3.14.0
# - AWS CLI 2.x
# - yq 4.44.3
# - argocd CLI
```

### Docker Image

Build and push the platform image:

```bash
# Build image
./scripts/docker-build-push.sh

# Image includes:
# - All Terraform/Terragrunt tools
# - kubectl, Helm, ArgoCD CLI
# - AWS CLI
# - Git, bash-completion, vim
```

### Version Management

Automated semantic versioning via CI/CD:

```bash
# Auto-increment patch version
./.github/workflows/version-bump.sh

# Manual version bump
echo "0.4.0" > .version
git add .version
git commit -m "Bump to v0.4.0"
git tag v0.4.0
git push origin main --tags
```

---

## 📚 Documentation

### Comprehensive Guides

- **[Proposal.md](Proposal.md)**: Complete architectural proposal with ApplicationSet details
- **[argocd/plans/deployment-plan.md](argocd/plans/deployment-plan.md)**: Consolidated deployment overview
- **[argocd/plans/Phase*.md](argocd/plans/)**: Detailed phase-by-phase execution guides

### Phase Documentation

Each phase includes:
- Objectives and prerequisites
- Step-by-step task breakdown
- Expected timelines
- Validation checkpoints
- Rollback procedures
- Success criteria

### Release Notes

- **[RELEASE_NOTES_v0.3.0.md](RELEASE_NOTES_v0.3.0.md)**: Major ACK deployment features
- **[RELEASE_NOTES_v0.3.2.md](RELEASE_NOTES_v0.3.2.md)**: CI/CD pipeline fixes

---

## 🧪 Testing

### Pre-Deployment Validation

```bash
# Validate Terragrunt configuration
./bootstrap/terragrunt-wrapper.sh validate

# Dry-run Terraform plan
./bootstrap/terragrunt-wrapper.sh plan

# Validate Kubernetes manifests
kustomize build argocd/spokes/spoke1/infrastructure/ | kubectl apply --dry-run=client -f -
```

### Post-Deployment Tests

```bash
# Network connectivity
kubectl run test-pod --image=busybox --rm -it -- wget -O- https://www.google.com

# DNS resolution
kubectl run test-dns --image=busybox --rm -it -- nslookup kubernetes.default

# ACK controller functionality
kubectl apply -f examples/test-iam-role.yaml
aws iam get-role --role-name test-role-from-ack
```

---

## 🐛 Troubleshooting

### Common Issues

**1. ApplicationSet not syncing**
```bash
# Check ApplicationSet controller logs
kubectl logs -n argocd deployment/argocd-applicationset-controller

# Verify cluster labels
kubectl get secret -n argocd <cluster-secret> -o yaml

# Check git repository access
argocd repo list
```

**2. ACK controller errors**
```bash
# Check IRSA configuration
kubectl describe sa -n ack-system ack-iam-controller

# Verify IAM role trust policy
aws iam get-role --role-name gen3-kro-hub-ack-iam-role --query 'Role.AssumeRolePolicyDocument'

# Check controller logs
kubectl logs -n ack-system -l app.kubernetes.io/name=ack-iam-controller
```

**3. KRO instance stuck**
```bash
# Check KRO controller logs
kubectl logs -n kro-system deployment/kro-controller

# Verify RGD exists
kubectl get resourcegraphdefinition eks-cluster

# Check instance status
kubectl get ekscluster spoke1-cluster -o yaml
```

**4. Terragrunt errors**
```bash
# Enable debug logging
./bootstrap/terragrunt-wrapper.sh plan --debug

# Check log files
tail -f outputs/logs/terragrunt-*.log

# Validate configuration
cd terraform/live && terragrunt validate
```

---

## 🚀 Roadmap

### v0.4.0 (Q1 2026)
- [ ] Multi-region hub support
- [ ] Automated spoke cluster scaling
- [ ] Enhanced monitoring dashboards
- [ ] Kyverno policy enforcement suite

### v0.5.0 (Q2 2026)
- [ ] GitLab integration
- [ ] Private registry support
- [ ] Disaster recovery automation
- [ ] Cost optimization recommendations

### v1.0.0 (Q3 2026)
- [ ] Production hardening
- [ ] Compliance reporting
- [ ] Advanced RBAC integration
- [ ] Multi-cloud support (Azure, GCP)

---

## 🤝 Contributing

We welcome contributions! Please see our contribution guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow GitOps principles
- Update documentation for changes
- Test in dev environment first
- Use semantic versioning
- Include rollback procedures

---

## 📜 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

Third-party licenses are documented in [third-party-licenses/](third-party-licenses/).

---

## 👥 Team

**Organization**: Indiana University
**Primary Maintainer**: BabasanmiAdeyemi (@boadeyem)
**Team**: RDS Team

### Contact

- **GitHub**: [indiana-university/gen3-kro](https://github.com/indiana-university/gen3-kro)
- **Issues**: [GitHub Issues](https://github.com/indiana-university/gen3-kro/issues)
- **Discussions**: [GitHub Discussions](https://github.com/indiana-university/gen3-kro/discussions)

---

## 🙏 Acknowledgments

- **AWS Controllers for Kubernetes (ACK)**: AWS team for excellent Kubernetes-native AWS resource management
- **ArgoCD**: Intuit for the powerful GitOps continuous delivery tool
- **KRO**: Kubernetes Resource Orchestrator team for advanced resource orchestration
- **Terraform**: HashiCorp for infrastructure-as-code tooling
- **Gen3**: University of Chicago for the Gen3 data commons platform

---

## 📖 Additional Resources

### External Documentation

- [AWS Controllers for Kubernetes](https://aws-controllers-k8s.github.io/community/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Gen3 Documentation](https://gen3.org/)

### Related Projects

- [terraform-aws-eks](https://github.com/terraform-aws-modules/terraform-aws-eks)
- [argocd-applicationset](https://github.com/argoproj/argo-cd/tree/master/applicationset)
- [kro](https://github.com/awslabs/kro)

---

**Built with ❤️ by the Indiana University RDS Team**
