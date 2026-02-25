# Platform Status — Pendings, Risks, Limitations & Future Work

Consolidated tracking document for the EKS Cluster Management Platform.
Items migrate here from `pending.md` once triaged and documented.

> **Last updated:** 2026-02-24

---

## Table of Contents

- [Pending Items](#pending-items)
- [Known Risks](#known-risks)
- [Current Limitations](#current-limitations)
- [Future Implementations](#future-implementations)

---

## Pending Items

Active work items that require code or configuration changes.

| ID | Summary | Blocking? | Status |
|----|---------|-----------|--------|
| C-BOOT1 | Bootstrap path double-prefix causes ArgoCD `ComparisonError` | Yes — blocks all ArgoCD reconciliation | Pending fix in `config/shared.auto.tfvars.json` |
| C-BOOT2 | No child ApplicationSets exist | Blocked on C-BOOT1 | Waiting |
| C-BOOT3 | KRO and ACK controllers not installed | Blocked on C-BOOT1 → C-BOOT2 | Waiting |
| C16 | Instances chart alignment with cluster-fleet overrides | Blocked on C-BOOT1 | Cannot validate until KRO running |
| C18 | Addons ApplicationSet environment selector verification | Blocked on C-BOOT2 | Cannot validate until child AppSets exist |

---

## Known Risks

Documented security and operational risks accepted for the current phase.

### R1: `--no-mfa` mode copies long-lived credentials

- **Source**: `scripts/mfa-session.sh` `--no-mfa` path
- **Risk**: Copies the user's static IAM credentials directly into `~/.aws/eks-devcontainer/credentials`. These credentials have no automatic expiry and grant full access to the source profile's permissions.
- **Mitigation**: The `--no-mfa` mode is intended for trusted development environments only. The credentials are bind-mounted into an isolated directory (not all of `~/.aws`), limiting exposure surface. Production workflows should always use the MFA path.
- **Future consideration**: Require `sts:GetSessionToken` even in `--no-mfa` mode to ensure all devcontainer credentials are time-limited.

### R2: `install.sh` credential check may return false positive

- **Source**: `scripts/install.sh` — `aws sts get-caller-identity` pre-flight check
- **Risk**: `sts:GetCallerIdentity` succeeds even with expired MFA sessions if the underlying IAM user credentials are still valid. This can give a false "credentials valid" result before plan/apply fails on actual API calls.
- **Mitigation**: Terraform itself validates permissions at apply time; the pre-flight check is a convenience, not a security gate. Failed applies are non-destructive (Terraform rolls back).
- **Future consideration**: Replace with a targeted API call (e.g., `aws eks describe-cluster`) that validates the session has the permissions actually needed.

### R3: KMS policies use `Resource: *` for key creation

- **Source**: `iam/*/ack/inline-policy.json` — `ManageKMSKeysForInfraGraph` statement
- **Risk**: `kms:CreateKey` cannot be scoped by ARN (key doesn't exist yet). Condition tags (`aws:RequestTag/ManagedBy`) are added but are only effective if RGD/ACK controllers tag keys at creation time. If a controller creates a key without the expected tag, modify/delete actions will be denied, but orphaned keys may result.
- **Mitigation**: Tag conditions are applied. `CreateKey` requires the `ManagedBy=ack` request tag. Post-creation actions require the resource to be tagged. Untagged keys cannot be modified or deleted via this policy.
- **Future verification**: Confirm that KRO RGD templates include the `ManagedBy: ack` tag on all KMS key resources.

### R4: Spoke ArgoCD secret naming patterns — coverage not yet verified

- **Source**: `iam/spoke*/argocd/inline-policy.json`
- **Risk**: Conditions scope Secrets Manager access to `argocd/*` and `argo-cd/*` prefixes, and SSM to `/argocd/*` and `/argo-cd/*`. If External Secrets Operator or other components store secrets under different prefixes, access will fail silently.
- **Mitigation**: No spoke secrets are deployed yet (ArgoCD hasn't reconciled). Pattern will be validated when ESO (wave 15) deploys and creates SecretStore resources.
- **Future verification**: After C-BOOT1 is resolved and spoke addons deploy, verify that ESO SecretStore definitions reference secrets matching these condition patterns.

---

## Current Limitations

Known constraints of the current platform state. These are expected and will be addressed as the platform evolves.

### L1: Environment addons are identical (dev/prod)

- **Files**: `argocd/addons/environments/dev/addons.yaml`, `argocd/addons/environments/prod/addons.yaml`
- **Status**: Both files have identical content. Environment-specific differentiation (e.g., different Helm chart versions, replica counts, or resource limits) is not yet implemented.
- **Rationale**: The structure is in place for per-environment overrides. Values will diverge as environment-specific requirements are defined.

### L2: Single RGD exists in resource-groups chart

- **File**: `argocd/charts/resource-groups/awsgen3infra1flat-rg.yaml`
- **Status**: Only the `AwsGen3Infra1Flat` ResourceGroupDefinition exists. The chart structure supports multiple RGD files — additional RGDs will be added as new infrastructure patterns are needed.

### L3: Workloads chart templates implemented

- **Files**: `argocd/charts/workloads/` — `Chart.yaml`, `values.yaml`, `templates/workloads.yaml`
- **Status**: The workloads chart template is implemented. It renders one ArgoCD Application per enabled workload entry. Infrastructure outputs are injected via the `fleet-workloads` ApplicationSet's `helm.parameters` (sourced from `argoCDClusterSecret` annotations). DB passwords use ExternalSecrets from AWS Secrets Manager on the spoke cluster.

### L4: Diagram SVG exports not generated

- **Files**: `docs/diagrams/*.drawio`
- **Status**: All 5 drawio files are updated with correct content, white backgrounds, and stale text removed. However, SVG exports for README embedding are not yet produced. No headless draw.io CLI is available in the container.
- **Workaround**: Export manually via VS Code draw.io extension → Export As → SVG.

---

## Future Implementations

Planned enhancements and improvements for upcoming iterations.

### F1: SSO integration for ArgoCD

Replace the `argocd-initial-admin-secret` password-based auth with GitHub/Okta SSO. After SSO is configured, disable local admin account.

### F2: Multi-RGD support

Extend `argocd/charts/resource-groups/` with additional ResourceGroupDefinitions for different infrastructure patterns (e.g., HA Aurora, multi-AZ ElastiCache, GPU-enabled EKS node groups).

### F3: Workload chart refinement

The basic `argocd/charts/workloads/templates/workloads.yaml` template is implemented. Future work: add per-workload ExternalSecret templates for DB credential injection, add health checks, and refine the `infraOutputs` parameter passthrough to individual Gen3 service charts.

### F4: Per-environment addon differentiation

Diverge `argocd/addons/environments/dev/addons.yaml` and `prod/addons.yaml` with environment-specific overrides (e.g., resource limits, replica counts, feature flags).

### F5: ACK `aws_managed` mode evaluation

The `aws_managed` ACK module path has been validated via Terraform plan (4 add, 2 change, 0 destroy). Decision pending on whether to switch from `self_managed` (ArgoCD Helm) to `aws_managed` (EKS Capability) for ACK controllers.

### F6: Hardened credential validation in `install.sh`

Replace `aws sts get-caller-identity` pre-flight check with a targeted API call (e.g., `aws eks describe-cluster`) that validates the session has the specific permissions needed for plan/apply.
