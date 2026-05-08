# Local CSOC Guide

The local CSOC is a host-based Kind cluster for RGD and KRO instance iteration. It uses the same `argocd/bootstrap` manifests as EKS, but ACK credentials are injected into Kubernetes because Kind has no EKS OIDC provider.

## Prerequisites

Install on the host: Kind 0.27.0, Docker, kubectl, Helm, AWS CLI v2, and jq.

Refresh AWS credentials before install or credential injection:

```bash
bash scripts/mfa-session.sh <MFA_CODE>
```

## First Run

```bash
bash scripts/kind-csoc.sh create install
bash scripts/kind-csoc.sh connect
```

`install` creates the Kind cluster, installs ArgoCD, applies every manifest in `argocd/bootstrap`, creates the local ArgoCD cluster secrets, and injects ACK credentials.

## Common Commands

| Command | Purpose |
|---------|---------|
| `bash scripts/kind-csoc.sh create` | Create the Kind cluster |
| `bash scripts/kind-csoc.sh install` | Install ArgoCD and bootstrap GitOps |
| `bash scripts/kind-csoc.sh inject-creds` | Refresh `ack/ack-aws-credentials` |
| `bash scripts/kind-csoc.sh connect` | Port-forward ArgoCD and print credentials |
| `bash scripts/kind-csoc.sh status` | Show cluster, ArgoCD, KRO, and Helm status |
| `bash scripts/kind-csoc.sh destroy` | Delete the Kind cluster |

## Paths

| Path | Purpose |
|------|---------|
| `argocd/csoc/kro/` | RGDs synced by `csoc-kro` |
| `argocd/csoc/controllers/kind-overrides/addons.yaml` | Local controller enablement |
| `argocd/spokes/spoke1/infrastucture-values.yaml` | Local spoke instance values |

The local fleet cluster secret uses ArgoCD cluster name `spoke1`, so `fleet-instances` reads `argocd/spokes/spoke1`.

## Operations

```bash
# Refresh expiring AWS credentials
bash scripts/mfa-session.sh <MFA_CODE>
bash scripts/kind-csoc.sh inject-creds

# Check current state
bash scripts/kind-csoc.sh status
bash scripts/reports/kro-status-report.sh

# Inspect RGD and instance health
kubectl get resourcegraphdefinitions
kubectl get awsgen3networksecurity1,awsgen3compute1 -A
```

RGD edits go under `argocd/csoc/kro/`. Instance edits go in `argocd/spokes/spoke1/infrastucture-values.yaml`.
