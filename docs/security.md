# Security

Security model, IAM design, credential management, and audit guidance for the EKS Cluster Management Platform.

## Table of Contents

- [IAM Architecture](#iam-architecture)
- [Cross-Account Trust Pattern](#cross-account-trust-pattern)
- [Credential Flow](#credential-flow)
- [Cross-Account ACK Trust Chain](#cross-account-ack-trust-chain)
- [Secrets Management](#secrets-management)
- [Gitignored Sensitive Files](#gitignored-sensitive-files)
- [ArgoCD Authentication](#argocd-authentication)
- [Kubernetes RBAC](#kubernetes-rbac)
- [Network Security](#network-security)
- [Audit Checklist](#audit-checklist)
- [Local CSOC Credential Model](#local-csoc-credential-model)

---

## IAM Architecture

The platform uses a **dual-role pattern** to isolate CSOC infrastructure credentials from spoke account resources.

```
CSOC Account
  └── ACK Source Role  (OIDC-trusted, short-lived credentials via IRSA)
        └── Assumes ──► Spoke Workload Roles  (one per spoke account)
                              └── Manages AWS resources in spoke accounts
```

### CSOC Roles

| Role | Trust | Purpose |
|------|-------|---------|
| `{csoc_alias}-csoc-role` | EKS OIDC Provider (IRSA) | ACK controllers assume this via pod identity. No long-lived keys. |
| `{csoc_alias}-argocd-role` | EKS OIDC Provider (IRSA) | ArgoCD access to AWS resources + STS AssumeRole to spoke ArgoCD roles |

### Spoke Roles

| Role | Trust | Purpose |
|------|-------|---------|
| `<spoke-alias>-spoke-role` | CSOC account root + ArnLike `*-csoc-role` | ACK cross-account resource management |
| `<namespace>-argocd-spoke-role` | `pods.eks.amazonaws.com` + CSOC root with ArnLike `*-argocd-role` | ArgoCD controller authentication to spoke EKS; created by RGD |

No IAM users or long-lived access keys are used for cross-account operations. All credentials are short-lived session tokens obtained via `sts:AssumeRole`.

---

## Cross-Account Trust Pattern

### Spoke Role Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<CSOC_ACCOUNT_ID>:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "ArnLike": {
          "aws:PrincipalArn": "arn:aws:iam::<CSOC_ACCOUNT_ID>:role/*-csoc-role"
        }
      }
    }
  ]
}
```

### Why Account-Root Principal?

The `arn:aws:iam::<CSOC>:root` principal is used instead of a direct role ARN because:

1. **Chicken-and-egg problem:** Spoke roles are created in Phase 1, before the CSOC EKS cluster exists. The ACK source role ARN does not exist yet.
2. **Account-root always exists** — it's a valid principal regardless of what roles are in the account.
3. **Security is not weakened** — the `ArnLike` condition restricts the actual caller to the specific role name pattern. Account-root is a convenience for principal resolution; conditions gatekeep who actually gets in.

### ArnLike Pattern

```
arn:aws:iam::<CSOC_ACCOUNT_ID>:role/*-csoc-role
```

- Wildcards are intentional — the role naming convention is enforced by Terraform, not by IAM.
- This pattern would allow any role matching `*-csoc-role` in the CSOC account. Ensure that naming convention is not used for unrelated roles.

> **Note:** `ExternalId` is not used. ACK does not pass an ExternalId during `sts:AssumeRole`. Caller restriction relies on the `ArnLike` condition alone.

---

## Credential Flow

### ACK Controller Credential Chain

```
1. ACK pod starts with ServiceAccount annotation:
   eks.amazonaws.com/role-arn: arn:aws:iam::<CSOC>:role/{csoc_alias}-csoc-role

2. EKS IRSA webhook injects env vars + projected volume (OIDC JWT token)

3. ACK controller calls sts:AssumeRoleWithWebIdentity
   → Receives short-lived session credentials for ACK source role (1h TTL)

4. To manage spoke resources, ACK calls sts:AssumeRole on the spoke workload role
   → arn:aws:iam::<SPOKE>:role/<spoke-alias>-spoke-role
   → Receives spoke session credentials (1h TTL)

5. ACK uses spoke credentials to create/update/delete AWS resources
```

### ArgoCD Spoke Authentication Chain

```
1. ArgoCD application-controller pod starts with ServiceAccount annotation:
   eks.amazonaws.com/role-arn: arn:aws:iam::<CSOC>:role/{csoc_alias}-argocd-role

2. EKS IRSA webhook injects env vars + projected volume (OIDC JWT token)

3. Controller encounters a cluster secret with awsAuthConfig:
   { "clusterName": "<spoke-name>", "roleARN": "<spoke-argocd-role-arn>" }

4. argocd-k8s-auth calls sts:AssumeRole on the spoke ArgoCD role:
   → arn:aws:iam::<SPOKE>:role/<namespace>-argocd-spoke-role
   → Trust policy allows *-argocd-role from CSOC account

5. Using the assumed role credentials, argocd-k8s-auth generates an EKS token:
   → Presigned STS GetCallerIdentity URL wrapped in a bearer token

6. EKS API authenticates the token → AccessEntry grants cluster-admin
   → ArgoCD syncs Applications to the spoke cluster
```

### Human Operator Credential Chain

```
1. Developer runs scripts/mfa-session.sh on HOST
   → Prompts for MFA token → calls sts:get-session-token
   → Writes temporary credentials to ~/.aws/eks-devcontainer/credentials [csoc]

2. ~/.aws/eks-devcontainer is bind-mounted into the devcontainer as ~/.aws
   → AWS_PROFILE=csoc is set in containerEnv

3. Container Terraform inherits credentials from environment
   → Uses them for CSOC account operations only

4. For spoke account operations (Phase 1):
   → Terragrunt uses profile configured in each unit's provider block
```

---

## Cross-Account ACK Trust Chain

This section describes the complete trust chain that enables ACK controllers running in the CSOC cluster to manage AWS resources in spoke accounts.

### End-to-End Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│ 1. EKS OIDC Provider                                                     │
│    The CSOC EKS cluster has an OpenID Connect (OIDC) identity provider   │
│    registered. This allows Kubernetes ServiceAccounts to assume IAM      │
│    roles without long-lived credentials.                                 │
│                                                                          │
│ 2. Pod Identity / IRSA                                                   │
│    ACK controller pods are annotated with:                               │
│    eks.amazonaws.com/role-arn: arn:aws:iam::<CSOC>:role/...-source      │
│    EKS injects a projected OIDC JWT token and AWS SDK env vars into the │
│    pod. The AWS SDK calls sts:AssumeRoleWithWebIdentity transparently.  │
│                                                                          │
│ 3. ACK Source Role (CSOC Account)                                        │
│    Trust policy: EKS OIDC provider (IRSA only — no human callers).      │
│    Permissions: Inline policy from iam/<alias>/ack/inline-policy.json.  │
│    This role has sts:AssumeRole permission to assume spoke workload     │
│    roles in target accounts.                                             │
│                                                                          │
│ 4. sts:AssumeRole → Spoke Workload Role                                 │
│    The ACK controller calls sts:AssumeRole on the spoke workload role:  │
│    arn:aws:iam::<SPOKE_ACCOUNT>:role/<spoke-alias>-spoke-role           │
│    No ExternalId — ACK does not pass it during sts:AssumeRole.          │
│                                                                          │
│ 5. Spoke Workload Role (Spoke Account)                                   │
│    Trust policy validates two conditions:                                │
│    a. Principal: CSOC account root (arn:aws:iam::<CSOC>:root)          │
│    b. ArnLike: aws:PrincipalArn matches *-csoc-role                    │
│    Permissions: Manages VPC, EKS, RDS, ElastiCache, KMS, S3, etc.     │
│                                                                          │
│ 6. Spoke Resource Management                                             │
│    ACK uses the spoke session credentials (1h TTL) to create, update,  │
│    and delete AWS resources as defined by KRO ResourceGroupDefinitions.  │
└──────────────────────────────────────────────────────────────────────────┘
```

### Security Properties

| Property | Mechanism |
|----------|-----------|
| No long-lived keys | OIDC → IRSA provides short-lived JWTs; all IAM credentials are session tokens |
| Caller restriction | `ArnLike` condition on spoke trust policy limits callers to `*-csoc-role` roles |
| Blast radius containment | Each spoke role has its own inline policy — permissions can be scoped per account |
| Credential timeout | Both the IRSA token (pod identity) and assumed-role sessions have 1h TTL |

### IAM Policy Files

| File | Applied To | Purpose |
|------|-----------|---------|
| `iam/_default/ack/inline-policy.json` | Fallback for any spoke without a custom policy | Default ACK permissions for managed services |
| `iam/spoke2/ack/inline-policy.json` | spoke2 ACK workload role | Custom permissions for spoke2 (currently uses `_default` content) |

> Spokes without a custom `iam/<alias>/ack/` directory automatically fall back to `iam/_default/ack/inline-policy.json`.

### Tag-Based Access Control (KMS)

KMS key management actions use tag-based conditions to limit scope:

- **CreateKey**: Requires `aws:RequestTag/ManagedBy = "ack"` — keys must be tagged at creation time
- **Modify/Delete actions**: Requires `aws:ResourceTag/ManagedBy = "ack"` — only tagged keys can be modified

This ensures ACK can only manage KMS keys it created. Untagged keys or keys tagged by other systems cannot be modified via this policy.

---

## Secrets Management

### AWS Secrets Manager

Git credentials for ArgoCD are stored in AWS Secrets Manager, not in git:

| Secret Name | Contents | Access |
|-------------|----------|--------|
| `gen3-argocd-github-app` | GitHub App private key (PEM) + App ID + Installation ID | CSOC ACK ArgoCD role via ESO |

The `argocd-bootstrap` Terraform module retrieves this secret at apply time and creates a `kubernetes_secret` in the `argocd` namespace. ArgoCD uses this secret to clone the git repository.

### Kubernetes Secrets

| Secret | Namespace | Contains | Source |
|--------|-----------|----------|--------|
| `{csoc_alias}-csoc-cluster-secret` | `argocd` | Cluster endpoint, CA, metadata | Terraform `argocd-bootstrap` module |
| `argocd-repo-{csoc_alias}` | `argocd` | GitHub App credentials | Terraform + AWS Secrets Manager |
| `argocd-initial-admin-secret` | `argocd` | ArgoCD admin password | ArgoCD Helm install (auto-generated) |

> Rotate `argocd-initial-admin-secret` after initial login. Use ArgoCD's account management to set a permanent password or configure SSO.

### External Secrets Operator

ESO is deployed in wave 15 to sync additional secrets from AWS Secrets Manager (e.g., database passwords, API keys) into Kubernetes namespaces as needed by spoke workloads.

---

## Gitignored Sensitive Files

The following files must **never** be committed to git. All are listed in `.gitignore`:

| File | Contents |
|------|----------|
| `config/shared.auto.tfvars.json` | AWS profiles, cluster config, spoke account IDs, backend config |
| `outputs/connect-csoc.sh` | Cluster connection script with embedded cluster name |
| `outputs/logs/` | Terraform plan/apply logs (may contain resource IDs) |
| `outputs/argo/` | ArgoCD resource dumps |
| `config/ssm-repo-secrets/input.json` | SSM repo secret input values |

### Verification

```bash
# Confirm shared config is gitignored
git check-ignore -v config/shared.auto.tfvars.json

# Check for accidentally staged sensitive files
git status --short | grep -E '\.json$|\.yaml$|\.txt$'

# Scan for secrets in staged files (requires gitleaks or similar)
gitleaks detect --staged
```

---

## ArgoCD Authentication

### Admin Password

Set during `helm_release.argocd` via `configs.secret.argocdServerAdminPassword`. The bcrypt hash is auto-generated by ArgoCD. The plaintext is exported as `$ARGOCD_ADMIN_PASSWORD` environment variable by `container-init.sh connect` (stored in `~/.container-env`, sourced by `.bashrc`).

**Recommended post-deploy actions:**
1. Log in to ArgoCD UI
2. Go to Settings → Accounts → Change password for `admin`
3. Or configure SSO (GitHub/Okta) and disable local users

### RBAC

ArgoCD RBAC is configured via `argocd-rbac-cm` ConfigMap. Default policy allows authenticated users read-only access. Admin users require the `role:admin` binding.

```bash
# Check current RBAC configuration
kubectl get configmap argocd-rbac-cm -n argocd -o yaml
```

### Git Repository Access

ArgoCD connects to the git repository using a GitHub App (not a personal access token or SSH key). GitHub Apps provide:
- **Fine-grained permissions** — read-only access to specific repositories
- **No user dependency** — credentials don't expire when a user leaves
- **Automatic token rotation** — installation tokens are short-lived (1h)

---

## Kubernetes RBAC

### ACK Controllers

Each ACK controller runs with a dedicated ServiceAccount bound to a ClusterRole. The ClusterRole grants permissions only for the specific AWS service's CRDs (e.g., `ec2.services.k8s.aws`).

### ArgoCD

ArgoCD runs with cluster-admin-equivalent RBAC to manage resources across all namespaces. This is the standard ArgoCD deployment pattern — restrict via ArgoCD's own RBAC, not Kubernetes RBAC.

### KRO Controller

KRO runs with permissions to create, read, update, and delete custom resources and the resources they expand into. Refer to the KRO Helm chart RBAC configuration for exact permissions.

---

## Network Security

### EKS API Server

The EKS cluster `endpoint_private_access = true` is set. Public access may be enabled for initial setup but should be restricted after the CSOC network is established.

```bash
# Check current endpoint access configuration
aws eks describe-cluster \
  --name <CSOC_ALIAS>-csoc-cluster \
  --query 'cluster.resourcesVpcConfig.{public: endpointPublicAccess, private: endpointPrivateAccess}'
```

### VPC Design

| Layer | CIDR | Access |
|-------|------|--------|
| EKS nodes | Private subnets | No direct internet ingress |
| NAT Gateway | Public subnets | Outbound internet for nodes |
| Control plane | AWS-managed | Accessible from VPC + authorized public CIDRs |

### Security Groups

EKS node security group allows:
- Inbound from control plane security group on all ports
- Outbound to all destinations (for package downloads, AWS API calls)
- Nodes communicate with each other within the cluster

### Cross-Account Traffic

All cross-account API calls go through AWS STS and service endpoints — no VPC peering or Transit Gateway is needed for ACK cross-account operations. ACK controllers call AWS APIs (HTTPS) using assumed-role credentials.

---

## Audit Checklist

Use this checklist before production deployment:

### IAM

- [ ] `shared.auto.tfvars.json` is gitignored and not tracked by git
- [ ] `terraform.auto.tfvars.json` (generated) is gitignored
- [ ] No IAM access keys exist for cross-account operations (all via `sts:AssumeRole`)
- [ ] Spoke workload role inline policies are scoped to minimum required permissions
- [ ] ACK source role trust policy is restricted to the EKS OIDC provider
- [ ] `ArnLike` condition is set on all spoke role trust policies

### Credentials

- [ ] MFA is enforced on developer IAM accounts (`scripts/mfa-session.sh` used for all ops)
- [ ] GitHub App credentials are stored in Secrets Manager, not in git
- [ ] ArgoCD admin password has been rotated from the initial auto-generated value
- [ ] ArgoCD admin password is only available via `$ARGOCD_ADMIN_PASSWORD` env var (not persisted to disk)

### Git

- [ ] No plaintext AWS account IDs in committed files (use variable references)
- [ ] `.gitignore` covers all items in [Gitignored Sensitive Files](#gitignored-sensitive-files)
- [ ] `argocd/bootstrap/*.yaml` contain no account-specific hardcoded values

### Kubernetes

- [ ] ArgoCD RBAC is configured with least-privilege for non-admin users
- [ ] `argocd-initial-admin-secret` has been rotated (or SSO configured)
- [ ] No secrets are stored as ConfigMaps (use TypedSecrets or ESO)

### Network

- [ ] EKS API server public access is restricted to authorized CIDRs (or disabled)
- [ ] Node security groups do not allow unrestricted inbound (`0.0.0.0/0 all`)

### Monitoring

- [ ] AWS CloudTrail is enabled in CSOC and spoke accounts
- [ ] `sts:AssumeRole` events are monitored for unexpected principals
- [ ] ArgoCD audit log is enabled (`argocd.log` for all ApplicationSet/sync events)

---

## Local CSOC Credential Model

The local CSOC uses a different credential model from the EKS CSOC:

### EKS CSOC — IRSA (No Long-Lived Keys)

```
ACK Pod → OIDC token → STS → Short-lived credentials
                           → AssumeRole → Spoke workload role
```

No long-lived credentials exist in the cluster. All credentials are obtained
via IRSA (IAM Roles for Service Accounts) using the EKS OIDC provider.

### Local CSOC — K8s Secret (MFA-Assumed-Role)

Kind does not have an OIDC provider, so IRSA is not available.

```
Developer runs: bash scripts/mfa-session.sh <MFA_CODE>
    → STS AssumeRole with MFA → writes ~/.aws/credentials [csoc]

bash scripts/kind-local-test.sh inject-creds
    → kubectl create secret ack-aws-credentials -n ack-system
    → ACK controllers read from this Secret
```

### Security Controls (Local CSOC)

| Control | Detail |
|---------|--------|
| MFA required | `mfa-session.sh` enforces MFA token for every session |
| Credential expiry | STS session tokens expire (typically 1–12 hours) |
| No git storage | `~/.aws/credentials` is never committed |
| K8s Secret scope | `ack-aws-credentials` lives only in `ack-system` namespace |
| No restart needed | ACK controllers re-read the Secret on next reconcile |

### Credential Renewal (Local CSOC)

```bash
# Step 1: Renew on host
bash scripts/mfa-session.sh <NEW_MFA_CODE>

# Step 2: Inject into cluster
bash scripts/kind-local-test.sh inject-creds

# Step 3: Verify
aws sts get-caller-identity --profile csoc
kubectl get secret ack-aws-credentials -n ack-system
```

> Never store the `ack-aws-credentials` Secret value in git, logs, or outputs.
