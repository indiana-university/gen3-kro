---
description: 'Local CSOC Kind cluster conventions, ArgoCD-managed test workflow, and debugging procedures'
applyTo: "scripts/kind-local-test.sh,scripts/kind-config.yaml,argocd/local-kind/**,config/**"
---

# Local CSOC Testing

## Kind Cluster Conventions

- Cluster name: `gen3-local` (context: `kind-gen3-local`)
- Config: `scripts/kind-config.yaml` — single control-plane, NodePort mappings
  - Port 30080 → ArgoCD UI
- Kind runs on the **host** (not inside a container)
- Kubeconfig: `~/.kube/config` (or set `KUBECONFIG` explicitly)

## ArgoCD-Managed Test Workflow

Tests are never applied manually with `kubectl apply`. All KRO capability
tests are deployed through ArgoCD.

### Add a new RGD (test or production)
Place it in `argocd/charts/resource-groups/templates/` (any `.yaml` file).
ArgoCD Application `kro-local-rgs` (sync-wave 10) picks it up on the next push.

### Add a test instance
- Non-AWS tests: `argocd/local-kind/test/tests/`
- Real-AWS tests: `argocd/local-kind/test/infrastructure/`

ArgoCD Application `kro-local-instances` (sync-wave 30) picks it up automatically.

### Push and observe
```bash
git add argocd/charts/resource-groups/templates/<new-rg>.yaml
git add argocd/local-kind/test/tests/<new-instance>.yaml
git commit -m "test: add KRO capability test N"
git push

kubectl get application -n argocd -w
kubectl get <kind-lowercase> -n <namespace> -w
```

### Verify results
```bash
# KRO instance status
kubectl get <kind-lowercase> <name> -n <namespace> -o yaml

# Tests 1-5 (ConfigMap-based)
kubectl get configmaps -n <namespace> -l test-name=<label>

# Tests 6-7 (Real ACK EC2)
kubectl get vpc,securitygroup,routetable,internetgateway -n <namespace>
kubectl get configmaps -n <namespace>
```

## Credentials Workflow

```bash
# 1. Renew MFA credentials
bash scripts/mfa-session.sh

# 2. Inject into cluster
bash scripts/kind-local-test.sh inject-creds

# 3. Verify ACK controllers are reconnected
kubectl get pods -n ack
```

## Full Lifecycle Commands

```bash
bash scripts/kind-local-test.sh create     # Create Kind cluster
bash scripts/kind-local-test.sh install    # Install ArgoCD + all addons
bash scripts/kind-local-test.sh inject-creds  # Inject AWS credentials
bash scripts/kind-local-test.sh delete     # Tear down cluster
```

## AWS Account ID Injection

The account ID is never in git. `kind-local-test.sh install` calls
`aws sts get-caller-identity` and writes the result as an annotation on the
ArgoCD cluster Secret. All downstream templates read it from there.
