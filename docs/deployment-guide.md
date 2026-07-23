# Deployment Guide

> **⚠️ Not for production use.** This platform is under active development. Follow these procedures in development/testing environments only.

Step-by-step procedures for deploying, managing, and tearing down the EKS Cluster Management Platform.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Phase 0 — Operator IAM Bootstrap (One-Time)](#phase-0--operator-iam-bootstrap-one-time)
- [CSOC Stack Deployment](#csoc-stack-deployment)
- [Verification](#verification)
- [Accessing ArgoCD](#accessing-argocd)
- [Ongoing Operations](#ongoing-operations)
- [Teardown](#teardown)
- [Troubleshooting](#troubleshooting)
- [Local CSOC Setup (Host-Based Kind)](#local-csoc-setup-host-based-kind)

---

## Prerequisites

### Tools Required

| Tool | Where | Purpose |
|------|-------|---------|
| AWS CLI v2 | Host | MFA session, account access |
| Terragrunt | Host or container | CSOC environment orchestration |
| Docker | Host | Dev container runtime |
| VS Code + Dev Containers | Host | Container environment |
| `jq`, `yq` | Container (pre-installed) | Config parsing |
| Terraform ≥ 1.13 | Container (pre-installed) | CSOC infrastructure |
| `kubectl` | Container (pre-installed) | Cluster inspection |
| `helm` | Container (pre-installed) | Helm chart validation |

### AWS Access Requirements

| Account | Role Needed | Used For |
|---------|-------------|---------|
| CSOC account | `TerraformExecutionRole` (or equivalent) | Creating all CSOC resources |
| Spoke Account 1 | `AdministratorAccess` | Creating ACK workload IAM roles |
| Spoke Account 2 | `AdministratorAccess` | Creating ACK workload IAM roles |

> The AWS profile used in the container is `csoc`. MFA credentials are written to `~/.aws/eks-devcontainer/credentials` on the host and bind-mounted into the container as `~/.aws`.

### Terraform Backend

The S3 backend bucket must exist before running Terragrunt/Terraform. Backend
config is read from `config/shared.auto.tfvars.json`.

### Workspace Location (WSL ext4)

> **IMPORTANT:** On Windows, the repository **must** live on a native Linux filesystem (WSL ext4), **not** on `/mnt/c/...` or other Windows-mounted paths. Terraform and Git require `chmod` support that NTFS/DrvFs mounts do not provide.

```bash
# Clone to WSL home directory (recommended)
cd ~/src  # or any ext4 path
git clone <repo-url> eks-cluster-mgmt
cd eks-cluster-mgmt
```

If you already cloned under `/mnt/c/...`, move or re-clone to a WSL-native path before proceeding.

---

## Initial Setup

### 1. Clone and Configure

```bash
# Clone to a WSL ext4 path (NOT /mnt/c/... — see Prerequisites above)
cd ~/src
git clone <repo-url> eks-cluster-mgmt
cd eks-cluster-mgmt

# Copy config template and populate it
cp config/shared.auto.tfvars.json.example  config/shared.auto.tfvars.json
```

### 2. Populate `config/shared.auto.tfvars.json`

Edit `config/shared.auto.tfvars.json`. Key fields to fill in:

```json
{
  "region": "us-east-1",
  "aws_profile": "csoc",
  "csoc_account_id": "111111111111",

  "csoc_alias": "rds-gen3",

  "backend_bucket": "my-tfstate-bucket",
  "backend_region": "us-east-1",

  "spokes": [
    { "alias": "spoke1", "enabled": true, "provider": { "aws_profile": "spoke1-profile", "region": "us-east-1", "account_id": "222222222222" } }
  ]
}
```

Terragrunt units own their state keys; `backend_bucket` and `backend_region`
select the shared backend location. See
`config/shared.auto.tfvars.json.example` for the full schema with all available
options.

### 3. Establish MFA Session (Host)

See [Phase 0](#phase-0--developer-identity-bootstrap-one-time) below for first-time MFA setup.
After MFA device is registered, run on the **HOST** before every container start:

```bash
bash scripts/mfa-session.sh <MFA_CODE>
# Writes temporary assumed-role credentials to ~/.aws/credentials [csoc]
```

---

## Phase 0 — Operator IAM Bootstrap (One-Time)

> Run once per operator. The stack references an existing IAM user, optionally
> manages its virtual MFA device, and creates function-specific operator roles.
> It never creates or deletes IAM users.

The deployed environment already uses the canonical backend key. New
environments start there directly.

### Step 1 — Review and create IAM resources

Operator access is independently stateful in `aws-csoc-operator-iam`. Review
the plan before applying it:

```bash
bash scripts/terragrunt-stack.sh operators-iam plan
bash scripts/terragrunt-stack.sh operators-iam apply
```

The initial configuration creates
`<csoc_alias>-csoc-operator-infrastructure-admin`, attaches one aggregate
assume-role policy to the configured existing user, and preserves or creates
the configured virtual MFA device. `platform-operator` remains disabled until
it has a user or exact external principal.

### Step 2 — Register MFA device with your authenticator

For a newly created device, retrieve the sensitive `mfa_enrollment` output
directly from the reviewed unit. Do not redirect it to a tracked file. Add the
seed or QR payload to an authenticator. Existing registered devices need no
enrollment step.

### Step 3 — Activate the MFA device

Wait for **two consecutive tokens** from your authenticator, then run:

```bash
aws iam enable-mfa-device \
  --user-name <YOUR_IAM_USERNAME> \
  --serial-number arn:aws:iam::<ACCOUNT_ID>:mfa/<MFA_DEVICE_NAME> \
  --authentication-code-1 <FIRST_CODE> \
  --authentication-code-2 <SECOND_CODE> \
  --profile <YOUR_ADMIN_PROFILE>
```

Success = zero output (exit 0). If you get `InvalidAuthenticationCode`, wait one cycle and try again.

### Step 4 — Generate non-secret operator mappings

```bash
bash scripts/operator-profile.sh
```

This explicit command writes ignored
`outputs/aws-csoc-operator-iam.json` mode 0600. It contains the source profile,
default role key, role ARNs, and MFA device ARNs only. Terraform does not
create workstation profile files.

### Step 5 — Write devcontainer credentials (HOST)

`mfa-session.sh` selects a role from the structured output and writes temporary
credentials to `~/.aws/eks-devcontainer/credentials` under `[csoc]`. The
devcontainer mounts only that directory.

**Option A — MFA role session (recommended):**
```bash
# Defaults to infrastructure-admin.
bash scripts/mfa-session.sh <MFA_CODE>

# Select another enabled role assigned to the user.
bash scripts/mfa-session.sh <MFA_CODE> --role-key platform-operator
```

**Option B — No MFA (copy admin profile credentials directly):**
```bash
# Copies static credentials from the source profile — no role assumption, no token expiry
bash scripts/mfa-session.sh --no-mfa
```

Both options write to `~/.aws/eks-devcontainer/credentials` `[csoc]`.
Run this **before** opening the devcontainer (or before rebuilding it).

### Step 6 — Open the devcontainer

```bash
# In VS Code
Cmd+Shift+P → Dev Containers: Reopen in Container

# Or from CLI with devcontainer CLI
devcontainer open .
```

`container-init.sh setup` runs once after creation and validates credentials.
`container-init.sh connect` runs on each start and reconnects only when the
cluster already exists. A successful credential check shows:
```
AWS identity: arn:aws:sts::<account>:assumed-role/<CSOC_ALIAS>-csoc-operator-infrastructure-admin/...
Using temporary credentials (assumed-role) — good
```

---

## CSOC Stack Deployment

Run Terragrunt from the host or devcontainer after credentials are available.
Use the prerequisite, core, and spoke-fleet-update stack entrypoints independently in
dependency order.

```bash
# From repo root
bash scripts/terragrunt-stack.sh csoc-cluster-core plan
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update plan
```

### What the Stack Creates

- The core stack creates VPC/EKS, controller IAM, and the Argo CD installation.
- The spoke-fleet-update stack creates one selected spoke's IAM, exact CSOC assume-role
  access, repository secrets, fleet secrets, and the bootstrap ApplicationSet.

### State Ownership

Operator IAM is the only currently populated state. The other six boundaries
begin directly at the canonical keys below:

| Unit | State key |
|------|-----------|
| Operator access | `prereq/aws-csoc-operator-iam/terraform.tfstate` |
| CSOC cluster | `csoc/aws-csoc-cluster/terraform.tfstate` |
| Controller IAM | `csoc/aws-csoc-controller-iam/terraform.tfstate` |
| Per-spoke IAM | `spokes/<alias>/aws-spoke-access-iam/terraform.tfstate` |
| CSOC spoke access | `csoc/aws-csoc-to-spoke-access/terraform.tfstate` |
| Argo CD install | `csoc/gitops-argocd-install/terraform.tfstate` |
| GitOps bootstrap | `csoc/gitops-argocd-bootstrap/terraform.tfstate` |

Review each core or fleet plan before any apply. Empty state for a
unit means Terraform will propose creates for that unit; do not apply until that
is expected for the target environment.

Apply and verify individual units in dependency order:

```bash
bash scripts/terragrunt-stack.sh csoc-cluster-core plan aws-csoc-cluster
bash scripts/terragrunt-stack.sh csoc-cluster-core apply aws-csoc-cluster
bash scripts/terragrunt-stack.sh csoc-cluster-core plan aws-csoc-controller-iam
bash scripts/terragrunt-stack.sh csoc-cluster-core plan gitops-argocd-install

TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update plan aws-spoke-access-iam
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update plan aws-csoc-to-spoke-access
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update plan gitops-argocd-bootstrap
```

Run the same unit plan after each apply and require zero changes before moving
to the next unit.

---

## Verification

### Cluster Connectivity

```bash
# Kubeconfig is updated by the connect stage
bash scripts/container-init.sh connect
kubectl get nodes
kubectl get ns
```

Expected namespaces after apply: `default`, `kube-system`, `kube-public`, `kube-node-lease`, `argocd`.

### ArgoCD Pods

```bash
kubectl get pods -n argocd
```

All pods should be in `Running` state:

| Pod | Role |
|-----|------|
| `argocd-application-controller-*` | Application reconciliation loop |
| `argocd-applicationset-controller-*` | ApplicationSet generation |
| `argocd-dex-server-*` | OIDC/SSO authentication |
| `argocd-notifications-controller-*` | Event notifications |
| `argocd-redis-*` | Internal cache |
| `argocd-repo-server-*` | Git repository operations |
| `argocd-server-*` | API + UI server |

### ArgoCD Applications

```bash
kubectl get applicationsets,applications -n argocd
```

After initial apply: `bootstrap` ApplicationSet and `bootstrap` Application should exist. The Application's sync status may show `Unknown` if the git branch has not been pushed yet — this is expected for GitOps.

### Bootstrap ApplicationSet Status

Once the git branch is live and ArgoCD can reach the repository:

```bash
# Check all applications
kubectl get applications -n argocd -o wide

# Check a specific application
kubectl describe application bootstrap -n argocd

# Watch sync progress
kubectl get applications -n argocd -w
```

### ACK Controllers

After addons sync (wave 1):

```bash
# Verify ACK controller pods
kubectl get pods -A | grep ack-

# Check ACK controller logs for cross-account assume
kubectl logs -n ack deployment/ec2-chart | tail -20
```

### KRO Instances

After fleet sync (wave 30):

```bash
# List KRO instances by kind (examples)
kubectl get awsgen3networksecurity1,awsgen3compute1 -A

# Or render the spoke KRO instances that ArgoCD applies
helm template kro-aws-instances argocd/csoc/helm/kro-aws-instances \
  -f argocd/spokes/spoke1/infrastructure-values.yaml | grep '^kind:'

# Check instance status
kubectl describe vpc spoke1-vpc -n spoke1
```

---

## Accessing ArgoCD

### Port-Forward Method

Run the devcontainer connection stage:

```bash
bash scripts/container-init.sh connect
```

This stage:
1. Refreshes kubeconfig for `{csoc_alias}-csoc-cluster`
2. Port-forwards ArgoCD server to `localhost:8080`
3. Opens the UI at `https://localhost:8080`

### Credentials

- **Username:** `admin`
- **Password:** `$ARGOCD_ADMIN_PASSWORD` in the container environment

```bash
printf '%s\n' "$ARGOCD_ADMIN_PASSWORD"
```

> The ArgoCD admin password is read from `argocd-initial-admin-secret` by
> `bash scripts/container-init.sh connect` and exported into the container
> environment when available.

### ArgoCD CLI

```bash
# Login
argocd login localhost:8080 \
  --username admin \
  --password "$ARGOCD_ADMIN_PASSWORD" \
  --insecure

# List applications
argocd app list

# Sync an application manually
argocd app sync bootstrap

# Check application health
argocd app get fleet --show-operation
```

---

## Ongoing Operations

### Adding a New Spoke Account

1. Add spoke config to `config/shared.auto.tfvars.json` under `spokes` array
2. Create `iam/<new-spoke-alias>/ack/inline-policy.json` (or rely on `_default`)
3. Add spoke values in `argocd/spokes/<new-spoke>/`
4. Run `bash scripts/terragrunt-stack.sh csoc-cluster-core plan`
5. Review the plan, then run `bash scripts/terragrunt-stack.sh csoc-cluster-core apply`

### Updating Addon Values

Edit the appropriate values file:

| Scope | File to Edit |
|-------|-------------|
| Controller defaults | `argocd/csoc/controllers/values.yaml` |
| Cluster-type controller overrides | `argocd/csoc/controllers/<cluster_type>-overrides/addons.yaml` |
| Spoke instances | `argocd/spokes/<spoke>/infrastructure-values.yaml` |

Push to git — ArgoCD will reconcile automatically.

### KRO Instance Changes

Edit `argocd/spokes/<spoke>/infrastructure-values.yaml` and push. ArgoCD will reconcile the `kro-aws-instances` chart, which cascades through KRO to ACK resources.

### Rotating Git Credentials

1. Rotate the GitHub App private key in AWS Secrets Manager (`git_secret_name`)
2. Delete and recreate the ArgoCD git repo secret:
   ```bash
   kubectl delete secret argocd-repo-<cluster-name> -n argocd
   TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update apply
   ```

### Renewing MFA Session

```bash
# On HOST — re-run before credentials expire (12h default)
bash scripts/mfa-session.sh <MFA_CODE>          # Option A: MFA (assumed-role)
bash scripts/mfa-session.sh --no-mfa            # Option B: admin static creds
# Writes to ~/.aws/eks-devcontainer/credentials [csoc]
# Rebuild or reopen the devcontainer to pick up refreshed credentials
```

---

## Teardown

> **Warning:** This destroys all AWS resources including the EKS cluster, VPC, and IAM roles. ACK-managed spoke resources must be deleted first.

### Step 1: Delete KRO Instances

```bash
helm template kro-aws-instances argocd/csoc/helm/kro-aws-instances \
  -f argocd/spokes/spoke1/infrastructure-values.yaml | kubectl delete -f -
# Wait for ACK to delete spoke resources (VPCs, EKS clusters, RDS...)
kubectl get vpc,cluster -A   # verify gone
```

### Step 2: Destroy CSOC Infrastructure

```bash
# From repo root
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update destroy
bash scripts/terragrunt-stack.sh csoc-cluster-core destroy
```

This runs the Terragrunt stack destroy flow for the CSOC split-state layout.

### Step 3: Destroy Operator IAM Prerequisites

```bash
# Only when intentionally removing the devcontainer IAM bootstrap path
bash scripts/terragrunt-stack.sh operators-iam destroy
```

---

## Troubleshooting

### Terraform Plan Fails: Provider Authentication

```
Error: error configuring Terraform AWS Provider: no valid credential sources found
```

**Fix:** Refresh credentials on the HOST (`bash scripts/mfa-session.sh <CODE>` or `--no-mfa`), then rebuild or reopen the devcontainer.

### EKS Cluster Not Reachable After Apply

```bash
# Refresh kubeconfig manually
aws eks update-kubeconfig \
  --name <CSOC_ALIAS>-csoc-cluster \
  --region us-east-1 \
  --profile csoc
```

### ArgoCD Application Stuck "Unknown"

Check if ArgoCD can reach the git repository:

```bash
kubectl exec -n argocd deploy/argocd-repo-server -- \
  argocd-repo-server --check-connection
```

Verify the git secret was created correctly:

```bash
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
kubectl describe secret argocd-repo-<CSOC_ALIAS>-csoc-cluster -n argocd
```

### ACK Cross-Account Assume Fails

Check the ACK source role ARN in the cluster secret annotation:

```bash
kubectl get secret <CSOC_ALIAS>-csoc-cluster-secret -n argocd -o jsonpath='{.metadata.annotations}'
```

Verify the spoke access-role trust policy allows the ACK controller role:

```bash
aws iam get-role \
  --role-name spoke1-ack-controller-access-role \
  --query 'Role.AssumeRolePolicyDocument' \
  --profile spoke1-admin
```

### Terraform State Lock

```
Error: Error acquiring the state lock
```

Check if a previous apply is still running. If the state is genuinely stuck:

```bash
terraform force-unlock <LOCK_ID>
```

Get lock ID from the error message or from the DynamoDB table.

### Helm Release Timeout

ArgoCD Helm releases can timeout if images are slow to pull. Increase timeout in the ApplicationSet `helm.timeout` value, or check image pull status:

```bash
kubectl get events -n argocd --sort-by='.firstTimestamp' | tail -20
kubectl describe pod -n ack -l app.kubernetes.io/name=ec2-chart
```

---

## Local CSOC Setup (Host-Based Kind)

The local CSOC workflow uses a Kind cluster on the developer's host machine.
No DevContainer is required — all commands run directly on the host.

> **Use case:** RGD authoring, capability testing, and iteration without EKS overhead.
> ACK controllers talk to **real AWS APIs** — not LocalStack.

### Prerequisites (Local CSOC)

| Tool | Version | Install |
|------|---------|---------|
| Kind | 0.27.0 | `curl -Lo kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64` |
| kubectl | 1.35.1 | Standard kubectl install |
| Helm | 3.16.1 | Standard helm install |
| AWS CLI v2 | 2.x | Standard AWS CLI install |
| Docker | any | Required for Kind node containers |

### Step 1 — Authenticate (Host)

```bash
bash scripts/mfa-session.sh <MFA_CODE>
```

Writes MFA-assumed-role credentials to `~/.aws/credentials [csoc]`.

### Step 2 — Create Kind Cluster + Install Stack

```bash
bash scripts/kind-csoc.sh create install
```

This runs in sequence:
1. `kind create cluster` using `scripts/kind-config.yaml`
2. Helm installs ArgoCD
3. Creates ArgoCD cluster Secrets for the local control plane and `spoke1`, then injects AWS account ID
4. Applies bootstrap ApplicationSets
5. ArgoCD reconciles: KRO → ACK controllers → RGDs → KRO instances

### Step 3 — Inject Credentials

After ArgoCD deploys the ACK controllers (wave 1), inject your credentials:

```bash
bash scripts/kind-csoc.sh inject-creds
```

Creates the `ack-aws-credentials` K8s Secret in `ack`.
Re-run this command every time credentials are renewed.

### Step 4 — Verify

```bash
# Check all pods are running
kubectl get pods --all-namespaces

# Check ArgoCD applications
kubectl get application -n argocd

# Check KRO RGDs are registered
kubectl get rgd
```

### Ongoing Local CSOC Operations

```bash
# Renew credentials
bash scripts/mfa-session.sh <MFA_CODE>
bash scripts/kind-csoc.sh inject-creds

# Check status
bash scripts/kind-csoc.sh status
bash scripts/reports/kro-status-report.sh

# Tear down
bash scripts/kind-csoc.sh destroy
```

See [docs/local-csoc-guide.md](local-csoc-guide.md) for the complete local CSOC reference.
