# kind-csoc.sh

Manages a local Kind cluster that mirrors the CSOC EKS setup for RGD authoring
and KRO capability testing. The Kind cluster runs ArgoCD, KRO, and ACK
controllers pointed at **real AWS APIs** — no LocalStack. No devcontainer or
EKS cluster is required.

## Usage

```bash
bash scripts/kind-csoc.sh [stage ...]

# Stages can be combined
bash scripts/kind-csoc.sh create install          # Cluster + full stack
bash scripts/kind-csoc.sh create install connect  # Full pipeline
```

## Stages

| Stage | Description |
|-------|-------------|
| `create` | Create the Kind cluster using `scripts/kind-config.yaml` and export kubeconfig |
| `install` | Install ArgoCD via Helm, apply bootstrap ApplicationSets, auto-inject ACK credentials |
| `inject-creds` | Refresh the ACK credentials Secret (also runs automatically during `install`) |
| `connect` | Retrieve the ArgoCD admin password and start a port-forward on `localhost:8080` |
| `test` | Apply test KRO instances and validate RGD reconciliation |
| `status` | Show pod and resource status across all namespaces |
| `destroy` | Delete the Kind cluster |
| `setup` | Validate AWS credentials and generate `config/local.env` |

## Prerequisites

Install on the host (not the devcontainer):

| Tool | Version |
|------|---------|
| `kind` | 0.27.0 |
| `kubectl` | any recent |
| `helm` | 3.x |
| `aws` CLI v2 | 2.x |
| `docker` | any recent |

AWS credentials at `~/.aws/credentials [csoc]` must be valid before `install`.
Run `bash scripts/mfa-session.sh <MFA_CODE>` on the host to refresh.

## Bootstrap Order (mirrors EKS CSOC)

```
Wave -30  KRO controller
Wave   1  ACK controllers (pointed at real AWS)
Wave  10  KRO ResourceGraphDefinitions
Wave  14  infrastructure-values ConfigMap
Wave  15  Network1
Wave  16  DNS1, Storage1
Wave  20  Compute1, Database1, Search1
Wave  24  OIDC1
Wave  25  AppIAM1, Advanced1, Messaging1
Wave  27  ClusterResources1
Wave  30  Helm1
```

## Spoke Values

KRO instance values are read from `argocd/spokes/spoke1/`:

```
argocd/spokes/spoke1/
  infrastructure-values.yaml   # per-spoke KRO instance values
  cluster-resources/           # PlatformHelm1 values
  <hostname>/                  # AppHelm1 values
```

## Full Guide

See [docs/local-csoc-guide.md](../docs/local-csoc-guide.md) for the complete
walkthrough including credential injection, RGD testing, and troubleshooting.
