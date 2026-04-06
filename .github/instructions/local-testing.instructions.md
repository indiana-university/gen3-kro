---
applyTo: "scripts/kind-local-test.sh,scripts/kind-config.yaml,argocd/cluster-fleet/local-aws-dev/**,config/**"
---

# Local CSOC Testing Instructions

These rules apply when editing Kind cluster scripts, ArgoCD instance manifests,
or local configuration files.

## Kind Cluster Conventions

- Cluster name: `gen3-local` (context: `kind-gen3-local`)
- Config: `scripts/kind-config.yaml` — single control-plane, NodePort mappings
- Port 30080 → ArgoCD UI
- Kind runs on the **host** (not inside a container). This workflow does not
  use `devcontainer.json`. The local CSOC is entirely host-side.
- Kubeconfig: `~/.kube/config` (default, or set `KUBECONFIG` explicitly)

## ArgoCD-Managed Test Workflow

Tests are **not** applied manually with `kubectl apply`. All KRO capability
tests are deployed through ArgoCD via two charts:

### 1. Register a new RGD (test or production)
Add it to `argocd/charts/resource-groups/templates/` (any `.yaml` file).
ArgoCD Application `kro-local-rgs` (sync-wave 10) picks it up on the next push.

### 2. Add a test instance
Create a standalone YAML file in `argocd/cluster-fleet/local-aws-dev/tests/`
(for non-AWS tests) or `infrastructure/` (for real-AWS tests).
ArgoCD Application `kro-local-instances` (directory source, sync-wave 30) picks
it up automatically on the next push.

### 3. Push and observe
```bash
git add argocd/charts/resource-groups/templates/<new-rg>.yaml
git add argocd/cluster-fleet/local-aws-dev/tests/<new-instance>.yaml
git commit -m "test: add KRO capability test N"
git push

# Watch ArgoCD sync
kubectl get application -n argocd

# Watch instance come up
kubectl get <kind-lowercase> -n <namespace> -w
```

### 4. Verify instance results
```bash
# Check KRO instance status
kubectl get <kind-lowercase> <name> -n <namespace> -o yaml

# Tests 1–5 (ConfigMap-based)
kubectl get configmaps -n <namespace> -l test-name=<label>

# Tests 6–7 (Real ACK EC2)
kubectl get vpc,securitygroup,routetable,internetgateway -n <namespace>
kubectl get configmaps -n <namespace>   # bridge / summary ConfigMaps
```

### 5. Cleanup
Delete the YAML file from `tests/` (or `infrastructure/`) → push → ArgoCD deletes
child resources. Remove the RGD from `resource-groups/templates/` → push →
ArgoCD deletes the CRD.

## KRO Capability Tests (ArgoCD-managed)

| # | Kind | RGD file | Instance key(s) | Resources | AWS? |
|---|------|----------|-----------------|-----------|------|
| 1 | `KroForEachTest` | `krotest01-foreach-rg.yaml` | `kro-foreach-basic`, `kro-foreach-cartesian` | ConfigMaps | No |
| 2 | `KroIncludeWhenTest` | `krotest02-includewhen-rg.yaml` | `kro-includewhen-minimal`, `kro-includewhen-full` | ConfigMaps | No |
| 3 | `KroBridgeProducer` | `krotest03-bridge-producer-rg.yaml` | `kro-bridge-producer` | ConfigMaps + Secret | No |
| 4 | `KroBridgeConsumer` | `krotest04-bridge-consumer-rg.yaml` | `kro-bridge-consumer` | ConfigMaps | No |
| 5 | `KroCELTest` | `krotest05-cel-expressions-rg.yaml` | `kro-cel-dev`, `kro-cel-prod` | ConfigMaps | No |
| 6 | `KroTest06SgConditional` | `krotest06-sg-conditional-rg.yaml` | `kro-sg-base-only`, `kro-sg-all-features` | ACK EC2 | Yes |
| 7a | `KroTest07Producer` | `krotest07a-cross-rgd-producer-rg.yaml` | `kro-crossrgd-producer` | ACK EC2 | Yes |
| 7b | `KroTest07Consumer` | `krotest07b-cross-rgd-consumer-rg.yaml` | `kro-crossrgd-consumer` | ACK EC2 | Yes |
| 8 | `KroChainedOrValueTest` | `krotest08-chained-orvalue-rg.yaml` | `kro-chained-orvalue-*` | ConfigMaps | No |

Instance sync-wave ordering: Tests 1–5 use wave 15; Test 4 bridge consumer and
Test 7b cross-RGD consumer use wave 20 (must wait for producers' bridge resources
to exist before trying externalRef).

## ACK Credentials (Real AWS)

ACK controllers talk directly to **real AWS APIs** (no LocalStack).
Credentials are MFA-assumed-role, written by `mfa-session.sh` on the host.

Because Kind has no OIDC provider (no IRSA), credentials are injected
as a K8s Secret (`ack-aws-credentials`) in the `ack` namespace.

After renewing credentials on the host, run:
```bash
bash scripts/kind-local-test.sh inject-creds
```

Tests 6, 7, and 8 (when using real AWS) require valid credentials.
Tests 1–5 are pure K8s (no AWS needed).

## Cluster Lifecycle

```bash
# Full cluster bootstrap (first time)
bash scripts/kind-local-test.sh create install

# Renew credentials only
bash scripts/kind-local-test.sh inject-creds

# Teardown
bash scripts/kind-local-test.sh delete
```
