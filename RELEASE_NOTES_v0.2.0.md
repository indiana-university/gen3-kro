# Release Notes - Version 0.2.0

**Release Date**: October 11, 2025  
**Branch**: staging  
**Release Type**: Minor Release

## Overview

Version 0.2.0 introduces a production-ready ACK (AWS Controllers for Kubernetes) deployment system to the hub cluster using a unified ApplicationSet pattern. This release significantly enhances the platform's ability to manage AWS resources natively through Kubernetes.

## 🚀 Major Features

### ACK Controllers Deployment

Successfully deployed AWS Controllers for Kubernetes to the hub cluster with the following controllers:

**Active Controllers:**
- ✅ **IAM Controller** (v1.2.1) - Managing IAM roles, policies, and access
- ✅ **EKS Controller** (v1.9.3) - Managing EKS clusters and node groups  
- ✅ **EC2 Controller** (v1.7.0) - Managing EC2 instances and networking resources
- ✅ **EFS Controller** (v1.1.1) - Managing Elastic File Systems

**Configured Controllers** (ready for enablement):
- CloudTrail Controller - Audit trail management
- CloudWatch Logs Controller - Log group management
- KMS Controller - Encryption key management
- OpenSearch Service Controller - Search domain management
- RDS Controller - Database management
- Route53 Controller - DNS management
- S3 Controller - Object storage management
- Secrets Manager Controller - Secrets management
- SNS Controller - Notification management
- SQS Controller - Message queue management
- WAFv2 Controller - Web application firewall management

### Unified ApplicationSet Pattern

Implemented a single, maintainable ApplicationSet (`ack-controllers.yaml`) that:
- Uses matrix generators to combine controller definitions with cluster selectors
- Enables per-cluster, per-controller control via cluster labels
- Automatically configures IRSA (IAM Roles for Service Accounts) for each controller
- Supports hub-specific and spoke-specific role ARN configurations
- Implements proper sync waves for ordered deployment

### Infrastructure Enhancements

- **Terragrunt Integration**: Enhanced Terragrunt wrapper for streamlined infrastructure deployment
- **ArgoCD Bootstrap Module**: Improved ArgoCD installation and configuration module
- **IAM Access Module**: Automated IAM role creation for ACK controllers with least-privilege policies
- **EKS Hub Module**: Optimized hub cluster provisioning with ACK support

## 🔧 Technical Improvements

### Configuration Management

1. **ACK Configuration Structure**:
   - Centralized defaults in `argocd/hub/values/ack-defaults.yaml`
   - Per-controller overrides in `argocd/hub/values/ack-overrides/`
   - Environment-specific configurations in `config/environments/`

2. **OCI Chart Integration**:
   - Migrated to official AWS ACK OCI Helm charts from public.ecr.aws
   - Fixed chart URL and versioning issues
   - Implemented proper chart version pinning

3. **Cluster Metadata Annotations**:
   - Added ACK-specific annotations for service accounts, roles, and namespaces
   - Implemented hub/spoke differentiation in role ARN selection
   - Enhanced cluster labeling for controller enablement

### Deployment Automation

- Automated namespace creation with `CreateNamespace=true` sync option
- Server-side apply for better resource management
- Self-healing and pruning enabled for GitOps compliance
- Exponential backoff retry strategy for transient failures

### Sync Wave Optimization

Implemented proper deployment ordering:
- Wave 1: Core controllers (IAM, EKS, EC2)
- Wave 3: Dependent controllers (EFS - requires EC2 networking)

## 🐛 Bug Fixes

- Fixed ACK Helm chart repository URLs and versions
- Resolved OCI chart syntax issues in ApplicationSets
- Corrected YAML parsing errors in chart field definitions
- Fixed finalizer issues in resource cleanup
- Removed deprecated `chart` field from OCI ApplicationSets
- Corrected JSON conversion handling for Helm values

## 📝 Configuration Changes

### New Files

- `argocd/hub/shared/applicationsets/ack-controllers.yaml` - Unified ACK controller deployment
- `argocd/hub/values/ack-defaults.yaml` - Default ACK configuration
- `argocd/hub/values/ack-overrides/*.yaml` - Per-controller configurations (15 controllers)
- `docs/README.md` - Comprehensive project documentation

### Modified Files

- `config/config.yaml` - Added ACK controller list and configuration
- `terraform/modules/argocd-bootstrap/` - Enhanced ArgoCD installation
- `terraform/modules/iam-access/` - Updated IAM role configurations
- `bootstrap/terragrunt-wrapper.sh` - Improved execution wrapper

## 🔐 Security Enhancements

- **IRSA Implementation**: All ACK controllers use IAM Roles for Service Accounts
- **Least Privilege IAM**: Each controller has minimal required permissions
- **Role Separation**: Distinct IAM roles for hub and spoke clusters
- **No Long-term Credentials**: Eliminated static AWS credentials

## 📊 Deployment Status

Current hub cluster deployment status:
```
Application                     Sync Status   Health Status
ack-applicationsets             Synced        Healthy
gen3-kro-hub-staging-ack-ec2    Synced        Healthy
gen3-kro-hub-staging-ack-efs    Synced        Healthy
gen3-kro-hub-staging-ack-eks    Synced        Healthy
gen3-kro-hub-staging-ack-iam    Synced        Progressing
```

## 🛠️ Developer Experience

- **Bootstrap Scripts**: Simplified cluster connection and management
- **Validation Scripts**: Pre-commit hooks for Terragrunt validation
- **Dev Container**: Full development environment with all tools pre-installed
- **Logging Utilities**: Standardized logging in shell scripts

## 📚 Documentation

- Comprehensive README with architecture overview
- ACK controller deployment guide
- Troubleshooting section for common issues
- Configuration examples and best practices
- Security considerations and guidelines

## ⚠️ Breaking Changes

None. This release is fully backward compatible with v0.1.0.

## 🔜 Known Limitations

- Some ACK controllers (RDS, S3, Route53, etc.) are configured but not yet enabled
- Hub-only controllers require manual cluster label updates for enablement
- Cross-cluster resource references need additional KRO resource graphs

## 📈 Metrics

- **Controllers Deployed**: 4 active, 11 configured
- **Git Commits**: 30+ commits focused on ACK integration
- **Configuration Files**: 15 controller-specific override files
- **Terraform Modules**: 4 modules enhanced/created
- **Lines of Code**: ~1000+ lines of YAML/Terraform added

## 🚦 Upgrade Path

From v0.1.0 to v0.2.0:

1. Pull latest changes from staging branch
2. Review and update `config/config.yaml` with ACK controller list
3. Run Terragrunt apply: `./bootstrap/terragrunt-wrapper.sh staging apply`
4. Verify ACK controllers: `kubectl get applications -n argocd | grep ack`
5. Enable additional controllers by updating cluster labels as needed

## 🙏 Contributors

- Platform Engineering Team
- Infrastructure Automation Team

## 📞 Support

For issues related to this release:
1. Check ArgoCD application sync status
2. Review ACK controller logs in `ack-system` namespace
3. Consult the troubleshooting section in docs/README.md
4. Contact the platform team

---

## Next Steps (v0.3.0 Roadmap)

- Enable additional ACK controllers (RDS, S3, Route53)
- Implement KRO resource graphs for complex AWS resource dependencies
- Add spoke cluster ACK controller deployment
- Implement cross-cluster resource sharing
- Add monitoring and alerting for ACK controllers
- Create example Gen3 deployment using ACK resources

---

**Full Changelog**: https://github.com/indiana-university/gen3-kro/compare/v0.1.0...v0.2.0
