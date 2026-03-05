# Platform Status — Pendings, Risks, Limitations & Future Work

Consolidated tracking document for the EKS Cluster Management Platform.
Items migrate here from `pending.md` once triaged and documented.

> **Last updated:** 2026-02-28

---

## Table of Contents

- [Pending Items](#pending-items)
- [Known Risks](#known-risks)
- [Current Limitations](#current-limitations)
- [Future Implementations](#future-implementations)

---

## Pending Items

**Platform Status: Fully Deployed ✅**

All core infrastructure and GitOps components are operational. Previous blocking items (C-BOOT1, C-BOOT2, C-BOOT3) have been resolved.

Active items requiring attention:

| ID | Summary | Blocking? | Status |
|----|---------|-----------|--------|
| P1 | Self-healing configuration review | No — functional | Active — needs decision |
| P2 | Spoke2 infrastructure not deployed | No — spoke1 operational | Values files created; awaiting deployment |
| M1 | ESO SecretStore pattern verification | No — runtime validation | Ready to verify |
| M2 | Workload deployment validation | No — infrastructure ready | Monitoring |

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
- **Future verification**: Verify that ESO SecretStore definitions reference secrets matching these condition patterns when ESO deploys on spoke clusters.

---

## Current Limitations

Known constraints of the current platform state. These are expected and will be addressed as the platform evolves.

### L1: Two RGDs exist in resource-groups chart

- **Files**: `argocd/charts/resource-groups/templates/awsgen3infra1flat-rg.yaml`, `argocd/charts/resource-groups/templates/awsgen3infra2flat-rg.yaml`
- **Status**: Two ResourceGraphDefinitions exist — `AwsGen3Infra1Flat` (original) and `AwsGen3Infra2Flat` (consolidated: includes multi-account resources, cluster-resources ArgoCD app, and gen3 ArgoCD app in a single dependency graph). The chart structure supports additional RGD files as new infrastructure patterns are needed.

### L2: Flat spoke deployment (apps + cluster-resources)

- **Files**: `argocd/charts/cluster-resources/`, `argocd/bootstrap/fleet-cluster-resources.yaml`, `argocd/bootstrap/fleet-gen3.yaml`, `argocd/cluster-fleet/<spoke>/apps.yaml`, `argocd/cluster-fleet/<spoke>/cluster-resources.yaml`
- **Status**: Spoke deployments use two flat ApplicationSets (no intermediate chart rendering Application CRDs):
  - `fleet-cluster-resources` (wave 40) — deploys cluster-level infra (external-secrets umbrella chart) directly to the spoke.
  - `fleet-gen3` (wave 50) — deploys gen3-helm umbrella chart directly to the spoke. Infrastructure outputs are injected via Helm parameters from argoCDClusterSecret annotations.
- **Architecture**: Matches gen3-gitops pattern: cluster-level-resources = ONE per EKS cluster, gen3 app = ONE per namespace/environment. Two levels of hierarchy (ApplicationSet → Application), not three.

### L3: Diagram SVG exports not generated

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

### F3: Gen3 service refinement

The `fleet-gen3` ApplicationSet deploys gen3-helm directly with `infraOutputs`
parameter injection (wave 50). Future work: add ExternalSecret resources for DB
credential injection on spoke clusters, add health checks, and integrate
fence-config / user-yaml-push templates from gen3-gitops.

### F4: ACK `aws_managed` mode evaluation

The `aws_managed` ACK module path has been validated via Terraform plan (4 add, 2 change, 0 destroy). Decision pending on whether to switch from `self_managed` (ArgoCD Helm) to `aws_managed` (EKS Capability) for ACK controllers.

### F5: Hardened credential validation in `install.sh`

Replace `aws sts get-caller-identity` pre-flight check with a targeted API call (e.g., `aws eks describe-cluster`) that validates the session has the specific permissions needed for plan/apply.
