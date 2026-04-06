# Local CSOC Guide

Step-by-step reference for the host-based local Kind CSOC workflow.

> **What is the local CSOC?**
> A Kind cluster on the developer's laptop that manages **real AWS resources**
> via KRO + ACK controllers, using the same RGDs and ArgoCD bootstrap chain as
> the EKS CSOC. Use it for RGD authoring, capability testing, and iteration
> without EKS overhead.

## Table of Contents

- [Prerequisites](#prerequisites)
- [First-Time Setup](#first-time-setup)
- [Ongoing Operations](#ongoing-operations)
- [Cluster Lifecycle Commands](#cluster-lifecycle-commands)
- [ArgoCD Access](#argocd-access)
- [Managing RGDs and Instances](#managing-rgds-and-instances)
- [Credential Renewal](#credential-renewal)
- [Troubleshooting](#troubleshooting)
- [Relationship to EKS CSOC](#relationship-to-eks-csoc)

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Kind | 0.27.0 | Local Kubernetes cluster |
| kubectl | 1.35.1 | Cluster CLI |
| Helm | 3.16.1 | Chart installs |
| AWS CLI v2 | 2.x | Credential validation + AWS API access |
| Docker (host daemon) | any | Kind requires Docker to create nodes |
| jq | system | JSON parsing in scripts |

> **Local CSOC is host-only** — no DevContainer needed. Kind runs on the host
> where the Docker daemon lives. Do not run `kind-local-test.sh` inside
> a Docker container.

### AWS Access Requirements

| Account | Minimum Permissions | Used For |
|---------|---------------------|---------|
| CSOC account (Tier 1) | MFA-assumed-role with EC2/EKS/IAM/RDS/etc. | ACK controllers → real AWS |

Credentials must be valid before running `inject-creds`. Obtain them:
```bash
bash scripts/mfa-session.sh <MFA_CODE>
```

---

## First-Time Setup

### 1. Create the Kind Cluster

```bash
bash scripts/kind-local-test.sh create
```

Creates the Kind cluster `gen3-local` using `scripts/kind-config.yaml`.
Exports kubeconfig to `~/.kube/config` (or `KUBECONFIG` if set).

### 2. Install the Full Stack

```bash
bash scripts/kind-local-test.sh install
```

This single stage:
1. Installs ArgoCD via Helm
2. Creates the ArgoCD cluster Secret with `fleet_member: control-plane` and
   injects the AWS account ID as an annotation
3. Applies bootstrap ApplicationSets (`local-addons`, `local-infra-instances`)
4. ArgoCD reconciles the full component stack:

| Wave | Component |
|------|-----------|
| -30 | KRO controller |
| 1 | ACK controllers (ec2, eks, iam, kms, opensearchservice, rds, s3, secretsmanager, sqs) |
| 10 | ResourceGraphDefinitions |
| 30 | KRO instances (infrastructure CRs) |

### 3. Inject AWS Credentials

```bash
bash scripts/kind-local-test.sh inject-creds
```

Creates/updates the `ack-aws-credentials` K8s Secret in `ack-system` from
`~/.aws/credentials`. Run this after every credential renewal.

### 4. Combine All Steps

```bash
bash scripts/kind-local-test.sh create install inject-creds
```

---

## Ongoing Operations

### Check Cluster Status

```bash
bash scripts/kind-local-test.sh status
# or
bash scripts/kro-status-report.sh
```

### Port-Forward ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Then open http://localhost:8080
```

Or use the NodePort (if configured in kind-config.yaml):
```
http://localhost:30080
```

### Get ArgoCD Admin Password

```bash
kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

---

## Cluster Lifecycle Commands

| Command | Effect |
|---------|--------|
| `create` | Create Kind cluster + export kubeconfig |
| `install` | Install ArgoCD + apply bootstrap ApplicationSets |
| `inject-creds` | Create/update ACK credentials Secret |
| `connect` | Retrieve ArgoCD password + start port-forward |
| `status` | Show pod/resource status across all namespaces |
| `destroy` | Delete Kind cluster (non-reversible) |
| `setup` | Validate AWS creds + generate `config/local.env` |

```bash
# Examples
bash scripts/kind-local-test.sh create install           # Cluster + full stack
bash scripts/kind-local-test.sh inject-creds            # Refresh creds only
bash scripts/kind-local-test.sh status                  # Check status
bash scripts/kind-local-test.sh destroy                 # Tear everything down
```

---

## ArgoCD Access

After `install`, ArgoCD manages all subsequent changes via GitOps:
- Push a change to `argocd/charts/resource-groups/templates/` → RGD updates
- Push a change to `argocd/cluster-fleet/local-aws-dev/` → instance updates
- ArgoCD polls every ~3 minutes (or use `argocd app sync <name>` for immediate)

---

## Managing RGDs and Instances

### Add a New RGD

1. Create `argocd/charts/resource-groups/templates/<name>-rg.yaml`
2. Commit and push
3. ArgoCD syncs `kro-local-rgs` automatically (wave 10)
4. KRO registers the new CRD

### Add a Production Instance

1. Create `argocd/cluster-fleet/local-aws-dev/infrastructure/<name>.yaml`
2. Commit and push
3. ArgoCD syncs `kro-local-instances` automatically (wave 30)

### Add a Test Instance

1. Create `argocd/cluster-fleet/local-aws-dev/tests/<name>.yaml`
2. Commit and push
3. ArgoCD syncs `kro-local-instances` automatically

### Remove an Instance

Delete the YAML file → commit and push → ArgoCD prunes the instance (wave 30).
ArgoCD auto-prune is enabled for instances.

---

## Credential Renewal

MFA credentials expire. When ACK controllers stop working:

```bash
# On the host — renew MFA session
bash scripts/mfa-session.sh <MFA_CODE>

# Then inject refreshed credentials into the Kind cluster
bash scripts/kind-local-test.sh inject-creds
```

Verify:
```bash
kubectl get secret ack-aws-credentials -n ack-system -o yaml
```

---

## Troubleshooting

### ACK resource stuck in `Syncing`

Check ACK controller logs:
```bash
kubectl logs -n ack-system deploy/ack-ec2-controller    # or other controller
```

Most common causes:
- Expired credentials → run `inject-creds`
- Missing IAM permissions → check CSOC role policy
- AWS API rate limit → wait and re-check

### KRO instance stuck or RGD `Inactive`

```bash
kubectl get rgd <name> -o yaml         # Check RGD status
kubectl get <kind-lower> <name> -o yaml  # Check instance conditions
```

If RGD is `Inactive` due to breaking schema change, see the breaking change
recovery steps in `.github/instructions/kro-rgd.instructions.md`.

### ArgoCD app `OutOfSync`

```bash
argocd app sync <app-name>
# or
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

### Kind cluster not found

```bash
kind get clusters          # Verify cluster exists
kubectl config get-contexts  # Verify context
kubectl config use-context kind-gen3-local
```

---

## Relationship to EKS CSOC

| Aspect | Local CSOC | EKS CSOC |
|--------|-----------|---------|
| Cluster | Kind on host | EKS (Terraform-managed) |
| Container | None (host-only) | VS Code DevContainer |
| ACK auth | K8s Secret (`ack-aws-credentials`) | IRSA (no long-lived keys) |
| Deployment | `kind-local-test.sh create install` | `scripts/install.sh apply` |
| Addons config | `argocd/addons/local/addons.yaml` | `argocd/addons/csoc/addons.yaml` |
| Spoke accounts | One (developer's Tier 1 account) | Multiple cross-account |
| Purpose | RGD authoring + capability testing | Production infrastructure management |

RGDs authored locally can be promoted to EKS with minimal change — same schema
conventions, same ACK annotation patterns, same sync-wave ordering.
