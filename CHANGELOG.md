# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-10-08

### Added

- **Hub-Spoke Architecture**: Centralized hub cluster managing multiple spoke clusters
- **KRO Integration**: Kubernetes Resource Orchestrator (KRO) for declarative spoke cluster provisioning
- **ArgoCD GitOps**: Complete GitOps workflow with ApplicationSets for fleet management
- **Shared RGD Library**: Reusable ResourceGraphDefinitions for EKS, VPC, IAM, EFS, and security groups
- **Terragrunt Orchestration**: DRY infrastructure-as-code with environment-specific overlays
- **Spoke Template**: Standardized template for creating new spoke clusters
- **Configuration System**: Single source of truth in `config/config.yaml` with environment overlays
- **ACK Controllers**: AWS Controllers for Kubernetes (IAM, EKS, EC2)
- **Documentation**:
  - Comprehensive architecture documentation
  - Hub and spoke deployment guides
  - Configuration reference
  - Development guide

### Changed

- Migrated from monolithic structure to hub-spoke architecture
- Centralized configuration in `config/` directory
- Moved KRO ResourceGraphDefinitions to shared library (`shared/kro-rgds/`)
- Reorganized ArgoCD manifests under `hub/argocd/`
- Updated README with quick start and architecture overview

### Security

- Sanitized all sensitive data (account IDs, internal details)
- Moved third-party licenses to dedicated folder
- Added NOTICE.md for third-party attributions

### Infrastructure

- Hub cluster configuration for staging environment
- Multi-account support via cross-account IAM roles
- VPC networking with public/private subnet architecture
- EKS managed node groups with autoscaling
- Encryption at rest with KMS

## [0.0.1] - 2025-10-05

### Added

- Initial project structure
- Basic Terraform modules
- Terragrunt wrapper script
- Development container configuration

---

[0.1.0]: https://github.com/indiana-university/gen3-kro/releases/tag/v0.1.0
[0.0.1]: https://github.com/indiana-university/gen3-kro/releases/tag/v0.0.1
