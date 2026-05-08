# Deployment Guide

> **⚠️ Not for production use.** This platform is under active development. Follow these procedures in development/testing environments only.

Step-by-step procedures for deploying, managing, and tearing down the EKS Cluster Management Platform.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Phase 0 — Developer Identity Bootstrap (One-Time)](#phase-0--developer-identity-bootstrap-one-time)
- [Phase 1 — Spoke IAM Roles (Host)](#phase-1--spoke-iam-roles-host)
- [Phase 2 — CSOC Cluster (Container)](#phase-2--csoc-cluster-container)
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
| Terragrunt | Host | Phase 1 spoke IAM deployment |
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

The S3 backend bucket must exist before running Terraform. Backend config (bucket, key, region) is extracted by `install.sh` from `config/shared.auto.tfvars.json`.

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
  "backend_key": "csoc-cluster/terraform.tfstate",
  "backend_region": "us-east-1",

  "spokes": [
    { "alias": "spoke1", "enabled": true, "provider": { "aws_profile": "spoke1-profile", "region": "us-east-1", "account_id": "222222222222" } }
  ]
}
```

See `config/shared.auto.tfvars.json.example` for the full schema with all available options.

### 3. Establish MFA Session (Host)

See [Phase 0](#phase-0--developer-identity-bootstrap-one-time) below for first-time MFA setup.
After MFA device is registered, run on the **HOST** before every container start:

```bash
bash scripts/mfa-session.sh <MFA_CODE>
# Writes temporary assumed-role credentials to ~/.aws/credentials [csoc]
```

---

## Phase 0 — Developer Identity Bootstrap (One-Time)

> **Run once per developer** — creates a virtual MFA device and scoped devcontainer role in AWS IAM.
> Skip if these already exist. Results are stored in `outputs/` and are gitignored.

### Step 1 — Create the IAM resources

Developer identity is now part of the Terragrunt IAM stack. Ensure `developer_identity` fields are populated in `config/shared.auto.tfvars.json`, then run:

```bash
cd terragrunt/live/aws/iam-setup
terragrunt stack run init
terragrunt stack run apply
```

This creates:
- Virtual MFA device in AWS IAM
- `{csoc_alias}-csoc-user` IAM role with MFA-required trust policy
- Inline assume-role policy attached to your IAM user
- `outputs/mfa-setup-instructions.txt` — MFA seed and activation command
- `outputs/aws-config-snippet.ini` — AWS profile block to copy to `~/.aws/config`

### Step 2 — Register MFA device with your authenticator

Open `outputs/mfa-setup-instructions.txt` and follow the instructions:

```bash
cat outputs/mfa-setup-instructions.txt
```

Add the account to your authenticator app (Google Authenticator, Authy, 1Password) using:
- **Method A:** Enter the Base32 seed manually
- **Method B:** Use a QR code generator with the `otpauth://` URI in the file

### Step 3 — Activate the MFA device

Wait for **two consecutive tokens** from your authenticator, then run:

```bash
# From outputs/mfa-setup-instructions.txt — exact command with your values:
aws iam enable-mfa-device \
  --user-name <YOUR_IAM_USERNAME> \
  --serial-number arn:aws:iam::<ACCOUNT_ID>:mfa/<CSOC_ALIAS>-csoc-user-mfa \
  --authentication-code-1 <FIRST_CODE> \
  --authentication-code-2 <SECOND_CODE> \
  --profile <YOUR_ADMIN_PROFILE>
```

Success = zero output (exit 0). If you get `InvalidAuthenticationCode`, wait one cycle and try again.

### Step 4 — (Optional) Add snippet to `~/.aws/config` for direct CLI use

> **Not required for devcontainer access.** `mfa-session.sh` reads `role_arn`, `source_profile`,
> and `mfa_serial` directly from `outputs/aws-config-snippet.ini`. Skip this step unless you want
> to use the `eks-devcontainer` profile with the AWS CLI on the HOST without running `mfa-session.sh`.

```bash
# Review the generated snippet
cat outputs/aws-config-snippet.ini

# Optionally append to host ~/.aws/config for direct CLI use
>> ~/.aws/config cat outputs/aws-config-snippet.ini
```

Snippet content for reference:
```ini
[profile eks-devcontainer]
role_arn = arn:aws:iam::<ACCOUNT_ID>:role/<CSOC_ALIAS>-csoc-user
source_profile = <YOUR_ADMIN_PROFILE>
mfa_serial = arn:aws:iam::<ACCOUNT_ID>:mfa/<CSOC_ALIAS>-csoc-user-mfa
region = us-east-1
output = yaml
duration_seconds = 43200
```

### Step 5 — Write devcontainer credentials (HOST)

`mfa-session.sh` auto-detects `role_arn`, `source_profile`, and `mfa_serial` from
`outputs/aws-config-snippet.ini` and writes credentials to `~/.aws/eks-devcontainer/credentials`
under `[csoc]`. The devcontainer mounts **only** that directory (not all of `~/.aws`).

**Option A — MFA (developer-identity role, recommended):**
```bash
# Assumes {csoc_alias}-csoc-user role using MFA → temporary credentials (12h)
bash scripts/mfa-session.sh <MFA_CODE>
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

The `container-init.sh` runs automatically and validates credentials. A successful init shows:
```
AWS identity: arn:aws:sts::<account>:assumed-role/<CSOC_ALIAS>-csoc-user/...
Using temporary credentials (assumed-role) — good
```

---

## Phase 1 — Spoke IAM Roles (Host)

Run Terragrunt **on the HOST** to create spoke workload IAM roles. These must exist before Phase 2 because ArgoCD needs them to assume for cross-account provisioning.

```bash
# From repo root on HOST
cd terragrunt/live/aws/iam-setup

# Preview what will be created
terragrunt stack run plan

# Apply (creates ACK workload roles in each spoke account)
terragrunt stack run apply
```

### What Phase 1 Creates

In each spoke account:
- IAM role `<spoke-alias>-spoke-role`
- Trust policy: `arn:aws:iam::<CSOC_ACCOUNT>:root` (account-root, always valid)
- Inline policy from `iam/<spoke-alias>/ack/inline-policy.json` (or `iam/_default/` fallback)

### Verify Phase 1

```bash
# Confirm roles exist in each spoke account
aws iam get-role \
  --role-name spoke1-spoke-role \
  --profile spoke1-admin

aws iam get-role \
  --role-name spoke2-spoke-role \
  --profile spoke2-admin
```

---

## Phase 2 — CSOC Cluster (Container)

Run inside the **dev container** (VS Code Dev Containers or `docker run`).

### Initialize Terraform Backend

```bash
# Inside container
bash scripts/install.sh init
```

This command:
1. Runs `terraform init` with backend config extracted from `config/shared.auto.tfvars.json`

### Plan

```bash
bash scripts/install.sh plan
```

Review the plan output. Key resources expected:
- `module.csoc_cluster.module.aws_csoc` — VPC, EKS cluster, IAM roles
- `module.csoc_cluster.module.argocd_bootstrap` — K8s secrets, Helm release

### Apply

```bash
bash scripts/install.sh apply
```

This command:
1. Runs `terraform apply -auto-approve`
2. Updates kubeconfig with EKS cluster credentials
3. Outputs the ArgoCD admin password to `outputs/argocd-password.txt`

Total resources: ~89 (VPC, EKS, IAM, ArgoCD, K8s secrets, Helm releases).

**Expected duration:** 20–30 minutes (EKS cluster creation is the longest step at ~15 min).

---

## Verification

### Cluster Connectivity

```bash
# Kubeconfig is updated automatically by install.sh
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
  -f argocd/spokes/spoke1/infrastucture-values.yaml | grep '^kind:'

# Check instance status
kubectl describe vpc spoke1-vpc -n spoke1
```

---

## Accessing ArgoCD

### Port-Forward Method

Run the generated connection script:

```bash
bash outputs/connect-csoc.sh
```

This script:
1. Refreshes kubeconfig for `{csoc_alias}-csoc-cluster`
2. Port-forwards ArgoCD server to `localhost:8080`
3. Opens the UI at `https://localhost:8080`

### Credentials

- **Username:** `admin`
- **Password:** Contents of `outputs/argocd-password.txt`

```bash
cat outputs/argocd-password.txt
```

> The ArgoCD admin password is the initial bcrypt hash from the `argocd-initial-admin-secret`. It is retrieved and saved by `install.sh` during apply.

### ArgoCD CLI

```bash
# Login
argocd login localhost:8080 \
  --username admin \
  --password "$(cat outputs/argocd-password.txt)" \
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
4. Run Phase 1 on HOST: `cd terragrunt/live/aws/iam-setup && terragrunt stack run apply`
5. Run Phase 2: `bash scripts/install.sh apply`

### Updating Addon Values

Edit the appropriate values file:

| Scope | File to Edit |
|-------|-------------|
| Controller defaults | `argocd/csoc/controllers/values.yaml` |
| Cluster-type controller overrides | `argocd/csoc/controllers/<cluster_type>-overrides/addons.yaml` |
| Spoke instances | `argocd/spokes/<spoke>/infrastucture-values.yaml` |

Push to git — ArgoCD will reconcile automatically.

### KRO Instance Changes

Edit `argocd/spokes/<spoke>/infrastucture-values.yaml` and push. ArgoCD will reconcile the `kro-aws-instances` chart, which cascades through KRO to ACK resources.

### Rotating Git Credentials

1. Rotate the GitHub App private key in AWS Secrets Manager (`git_secret_name`)
2. Delete and recreate the ArgoCD git repo secret:
   ```bash
   kubectl delete secret argocd-repo-<cluster-name> -n argocd
   bash scripts/install.sh apply   # re-creates the secret from Secrets Manager
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
  -f argocd/spokes/spoke1/infrastucture-values.yaml | kubectl delete -f -
# Wait for ACK to delete spoke resources (VPCs, EKS clusters, RDS...)
kubectl get vpc,cluster -A   # verify gone
```

### Step 2: Destroy CSOC Infrastructure

```bash
# Inside container
bash scripts/destroy.sh
```

This runs `terraform destroy` and cleans up kubeconfig entries.

### Step 3: Destroy Spoke IAM Roles

```bash
# On HOST
cd terragrunt/live/aws/iam-setup
terragrunt stack run destroy
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

Verify the spoke workload role trust policy allows the source role:

```bash
aws iam get-role \
  --role-name spoke1-spoke-role \
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
