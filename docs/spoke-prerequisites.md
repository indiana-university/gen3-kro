# Gen3 Spoke Deployment Prerequisites

> Prerequisites that must exist **before** deploying each spoke's
> RGD instances or Helm applications. Items marked **MANUAL** require
> human action; all others are created by Terraform, Terragrunt, or ArgoCD.

---

## Phase 0 — One-Time Account Bootstrap

These are performed once per AWS Organization / CSOC setup.

### 0.1 Terraform State Backend (Manual)

An S3 bucket for Terraform remote state. Must exist before any
`terraform init`.

```bash
aws s3api create-bucket --bucket <state-bucket-name> --region us-east-1
```

Configure in `config/shared.auto.tfvars.json`:
```json
{
  "backend_bucket": "<state-bucket-name>",
  "backend_key": "terraform.tfstate",
  "backend_region": "us-east-1"
}
```

### 0.2 Central Configuration File (Manual)

Copy and populate the central config:

```bash
cp config/shared.auto.tfvars.json.example config/shared.auto.tfvars.json
```

Required fields: AWS account IDs, profile names, spoke definitions,
CIDR ranges, cluster settings. This file drives all Terraform and
Terragrunt operations.

### 0.3 Developer Identity (Semi-Manual)

Virtual MFA device + scoped IAM role for DevContainer access.

```bash
cd terragrunt/live/aws/iam-setup
terragrunt stack run apply
```

Creates `{csoc_alias}-csoc-user` IAM role with MFA-required trust
policy. Outputs `mfa-setup-instructions.txt` with the authenticator
app QR code/secret. MFA device registration in the authenticator app
is manual.

### 0.4 GitHub App Credentials (Semi-Manual)

ArgoCD needs git repository access via a GitHub App.

1. Create a GitHub App with repository read permissions (manual)
2. Store credentials in Secrets Manager:
   ```bash
   cp config/ssm-repo-secrets/input.json.example config/ssm-repo-secrets/input.json
   # Populate with App ID, Installation ID, private key PEM
   bash scripts/ssm-repo-secrets/push-ssm-secrets.sh
   ```

---

## Phase 1 — Per-Spoke IAM Roles (Host / Terragrunt)

Run once per new spoke account, from the host machine.

### 1.1 ACK Spoke Workload Role

One IAM role per spoke (`<spoke-alias>-spoke-role`) with account-root
trust + ArnLike condition restricting to `*-csoc-role` callers.
Permissions come from `iam/<spoke>/ack/inline-policy.json` (or
`iam/_default/ack/` fallback).

```bash
cd terragrunt/live/aws/iam-setup
terragrunt stack run apply
```

Reads spoke definitions from `shared.auto.tfvars.json`.

---

## Phase 2 — CSOC EKS Cluster (Container / Terraform)

Run from inside the DevContainer after Phase 1.

### 2.1 CSOC VPC + EKS Cluster + OIDC Provider

```bash
bash scripts/install.sh apply
```

Creates: VPC, subnets, NAT gateway, IGW, EKS cluster with OIDC
provider, and all supporting IAM roles.

### 2.2 ACK Source IAM Role (IRSA)

`{csoc_alias}-csoc-role` — OIDC-trusted role assumed by ACK controller
pods via IRSA. Has `sts:AssumeRole` permission to assume spoke
workload roles. Created by `install.sh apply`.

### 2.3 ArgoCD IAM Role (IRSA)

`{csoc_alias}-argocd-role` — OIDC-trusted for ArgoCD server +
application-controller. Can assume spoke ArgoCD roles for cross-cluster
deployment. Created by `install.sh apply`.

### 2.4 External Secrets Pod Identity

EKS Pod Identity association granting the ESO service account access
to Secrets Manager, SSM, and KMS. Created by `install.sh apply`.

### 2.5 ArgoCD + Bootstrap ApplicationSet

ArgoCD is installed via Helm with custom health checks for KRO CRDs.
The bootstrap ApplicationSet creates the full ArgoCD chain. Both
created by `install.sh apply`.

### 2.6 ArgoCD Cluster Secrets

- **CSOC cluster secret**: Labels `fleet_member: control-plane`,
  annotations with repo URLs, region, ACK role ARN, spoke account data.
- **Per-spoke fleet secrets**: One per spoke, labeled
  `fleet_member: fleet-spoke-infra`, carrying spoke alias and account ID.

Both created by Terraform `argocd-bootstrap` module.

---

## Phase 3 — ACK Multi-Account (ArgoCD Wave 5)

Automated by ArgoCD — no manual steps, but must complete before
instances deploy.

### 3.1 Spoke Namespaces with CARM Annotations

K8s Namespace per spoke annotated with:
- `services.k8s.aws/owner-account-id`
- `services.k8s.aws/owner-account-role-arn`

RGDs read the owner-account-id via `spokeNamespace` externalRef.

### 3.2 ACK Role Account Map

`ack-role-account-map` ConfigMap in `ack` namespace mapping account
IDs to role ARNs for CARM cross-account resolution.

### 3.3 ACK IAMRoleSelector CRs

One per spoke, mapping the spoke role ARN to the spoke namespace.

All created by `ack-multi-acct` ApplicationSet → `argocd/charts/multi-acct/`.

---

## Per-Tier Prerequisites

### Tier 0 — Foundation1

| Prerequisite | Source | Automated? |
|---|---|---|
| Spoke namespace with `owner-account-id` annotation | Phase 3 (CARM) | Yes |
| ACK controllers: ec2, kms, s3 | ArgoCD wave 1 | Yes |

No manual prerequisites.

### Tier 1 — Database1

| Prerequisite | Source | Automated? |
|---|---|---|
| Foundation1 deployed with `databaseEnabled: true` | Creates `databasePrepBridge` ConfigMap | Yes |
| **Aurora master password K8s Secret** | **Manual** | **No** |
| ACK controllers: rds, secretsmanager | ArgoCD wave 1 | Yes |

**Manual step** — create the Aurora master password before deploying:
```bash
kubectl create secret generic aurora-master-password \
  -n <spoke-namespace> \
  --from-literal=password='<secure-password>'
```

The Database1 RGD references this via `masterPasswordSecretName` /
`masterPasswordSecretKey` schema fields.

> **Future**: Use `manageMasterUserPassword: true` (Aurora-managed
> password in Secrets Manager) or ExternalSecrets to automate this.

### Tier 2 — Search1

| Prerequisite | Source | Automated? |
|---|---|---|
| Foundation1 deployed with `searchEnabled: true` | Creates `searchPrepBridge` ConfigMap | Yes |
| Foundation1's `foundationBridge` ConfigMap | Created by Foundation1 | Yes |
| ACK controllers: opensearchservice | ArgoCD wave 1 | Yes |

No manual prerequisites.

### Tier 3 — Compute2

| Prerequisite | Source | Automated? |
|---|---|---|
| Foundation1 deployed with `computeEnabled: true` | Creates `computePrepBridge` ConfigMap | Yes |
| Foundation1's `foundationBridge` ConfigMap | Created by Foundation1 | Yes |
| ACK controllers: ec2, eks, iam | ArgoCD wave 1 | Yes |

No manual prerequisites.

### Tier 4 — AppIAM1

| Prerequisite | Source | Automated? |
|---|---|---|
| Foundation1's `foundationBridge` ConfigMap | Created by Foundation1 | Yes |
| Compute2's `computeBridge` ConfigMap | Created by Compute2 | Yes |
| ACK controllers: iam | ArgoCD wave 1 | Yes |

No manual prerequisites.

### Tier 5 — Helm1 (Gen3 Application)

| Prerequisite | Source | Automated? |
|---|---|---|
| Compute2's `computeBridge` ConfigMap (EKS endpoint, cluster name) | Created by Compute2 | Yes |
| Foundation1's `foundationBridge` ConfigMap (S3 ARNs, KMS ARNs) | Created by Foundation1 | Yes |
| Spoke ArgoCD cluster secret (created by Compute2 RGD) | Created by Compute2 argoCDClusterSecret | Yes |
| External Secrets Operator on spoke (wave 40) | ArgoCD cluster-resources chart | Yes |
| **DNS records for hostname** | **Manual — Route53 / DNS provider** | **No** |
| **TLS certificates** | **Manual — ACM / cert-manager** | **No** |
| **Identity Provider (Google/OIDC)** | **Manual — register OAuth app** | **No** |
| **Per-service secrets in Secrets Manager** | **Partially automated** | **Partial** |

**Manual steps**:

1. **DNS**: Create A/CNAME records pointing `<hostname>` to the spoke
   EKS ALB/NLB endpoint.

2. **TLS**: Provision TLS certificates via ACM (AWS) or cert-manager.

3. **Identity Provider**: Register an OAuth application with
   Google/OIDC provider. Store client ID and secret in Secrets Manager.
   Referenced by fence's ExternalSecret configuration.

4. **Per-service secrets**: Some are created by AppIAM1 RGD
   (Secrets Manager entries for fence, indexd, etc.). Others may need
   manual population (e.g., google-app-creds, fence-config YAML).

### Tier 6 — Observability1

| Prerequisite | Source | Automated? |
|---|---|---|
| Compute2's `computeBridge` ConfigMap (EKS endpoint) | Created by Compute2 | Yes |

No manual prerequisites.

---

## Recurring Maintenance

### MFA Credential Renewal

Temporary credentials expire after 12 hours. Re-run from the host:

```bash
# gen3-kro (EKS/IRSA)
bash scripts/mfa-session.sh <MFA_CODE>

# gen3-dev (Kind — also inject into cluster)
bash scripts/kind-local-test.sh inject-creds
```

---

## gen3-dev Specific Prerequisites

gen3-dev uses Kind instead of EKS. These replace Phases 1–3 above.

| Step | Command | Replaces |
|---|---|---|
| Create Kind cluster | `bash scripts/kind-local-test.sh create` | Phase 2 (EKS) |
| Install ArgoCD + KRO + ACK | `bash scripts/kind-local-test.sh install` | Phase 2 + 3 |
| Inject AWS credentials | `bash scripts/kind-local-test.sh inject-creds` | IRSA |

gen3-dev has no IRSA, no multi-account CARM, and no Terraform layer.
AWS credentials are injected as a K8s Secret and patched into ACK
controller Deployments. The AWS account ID is resolved at runtime via
`aws sts get-caller-identity` and set as an annotation on the ArgoCD
cluster Secret.

---

## Summary of Manual Prerequisites

| # | Item | When | Blocking Tier |
|---|---|---|---|
| 1 | S3 state backend bucket | Phase 0 (once) | All |
| 2 | `shared.auto.tfvars.json` configuration | Phase 0 (once) | All |
| 3 | MFA device registration | Phase 0 (once) | All |
| 4 | GitHub App creation + SSM push | Phase 0 (once) | All |
| 5 | MFA session renewal | Recurring (~12h) | All |
| 6 | Aurora master password K8s Secret | Before Tier 1 | Database1 |
| 7 | DNS records for hostname | Before Tier 5 | Helm1 |
| 8 | TLS certificates | Before Tier 5 | Helm1 |
| 9 | Identity Provider registration | Before Tier 5 | Helm1 (fence) |
| 10 | Per-service secrets population | Before Tier 5 | Helm1 |
