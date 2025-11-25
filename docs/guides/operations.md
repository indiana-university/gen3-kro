# Operations Guide

Day-to-day workflows for planning/applying, syncing ArgoCD, rotating credentials, and troubleshooting.

## Daily Operations Checklist

### Monitor
```bash
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running
argocd app list
argocd app get <app_name> --refresh
cd live/<provider>/<region>/<csoc_alias> && terragrunt plan --all --terragrunt-non-interactive
```

### Logs
```bash
./outputs/logs/terragrunt-*.log
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f
kubectl logs -n <namespace> -l app.kubernetes.io/name=<app_name>
```

## Planning and Applying Infrastructure Changes

### Plan Changes

Plan changes:
```bash
cd live/<provider>/<region>/<csoc_alias>
terragrunt plan --all 2>&1 | tee outputs/logs/plan-$(date +%Y%m%d-%H%M%S).log
```
Verify adds/changes look expected and avoid surprise destroys (VPC CIDR changes force replacement).

### Apply Changes

After reviewing plan:

```bash
terragrunt apply --all 2>&1 | tee outputs/logs/apply-$(date +%Y%m%d-%H%M%S).log
```

After apply, check outputs and workloads:
```bash
terragrunt output --all
kubectl get nodes
kubectl get pods -n <new-addon-namespace>
```

### Targeted Apply (Single Unit)

To apply changes to a specific Terragrunt unit (note: dependencies will still be processed):

```bash
cd live/<provider>/<region>/<csoc_alias>
terragrunt apply --terragrunt-include-dir units/csoc
```

## Syncing ArgoCD Applications

Sync all:
```bash
argocd app sync -l argocd.argoproj.io/instance=csoc-addons
argocd app sync -l argocd.argoproj.io/instance=graphs
```
Sync specific/refresh:
```bash
argocd app sync csoc-addons-kro
argocd app get csoc-addons-kro --refresh
argocd app sync csoc-addons-kro --prune --force
```
KRO uses sync wave -1; other addons use 0. Check waves with `kubectl get applications -n argocd -o json | jq ...`.

## Credential Rotation

### AWS Credentials

**AWS keys:** create new key, update `~/.aws/credentials`, restart devcontainer, verify with `aws sts get-caller-identity --profile gen3-dev`, then remove old key. Pod Identity roles rotate via Terraform (no manual step).

### ArgoCD Admin Password

**ArgoCD admin:** `NEW_PASSWORD=$(openssl rand -base64 32)` then `argocd account update-password --current-password <current> --new-password $NEW_PASSWORD` and store it in `outputs/argo/admin-password.txt`.

### Kubernetes Service Account Tokens

Tokens auto-rotate by Kubernetes. For manual rotation:

```bash
kubectl delete secret -n <namespace> <service-account-token-secret>
kubectl get sa -n <namespace> <service-account> -o yaml
# New token auto-generated
```

## Troubleshooting

### Terraform State Drift

**Terraform drift:** `terragrunt plan --all --detailed-exitcode` (code 2 = drift). Import or apply to reconcile. Common causes: console edits to SGs, autoscaled node counts, external IAM policy changes.

### ArgoCD Application Stuck

**ArgoCD app stuck:** `argocd app get --refresh`, check pods, view controller logs, force sync (`--force --prune`); delete app as last resort (ApplicationSet recreates).

### Pod Identity Authentication Failures

**Pod Identity failures:** check association (`aws eks list-pod-identity-associations`), service account annotation, IAM role/policy. Update policy if needed, `terragrunt apply --all`, then `kubectl rollout restart` the addon.

### State Lock Issues

**State lock issues:** confirm no active Terragrunt, use `terragrunt force-unlock <lock-id>`, or delete the DynamoDB lock item only if sure.

### Cluster Upgrade Failures

**Cluster upgrade fails:** check `aws eks describe-cluster`, review CloudFormation events, confirm addons/node groups support the version; rollback and retry once issues fixed.

### Checking Logs

Terragrunt logs: `./outputs/logs/terragrunt-*.log | grep -i error`. ArgoCD logs: controller, repo-server, server (`kubectl logs -n argocd -l app.kubernetes.io/name=...`).

## Backup and Recovery

### Backup Terraform State

State backends are versioned (S3/Storage/GCS). To restore a version, fetch it from the backend (e.g., `aws s3api get-object ... --version-id <id> terraform.tfstate`).

### Backup ArgoCD Applications

ArgoCD definitions live in Git; export with `argocd app get ... -o yaml` if needed.

### Disaster Recovery

Complete cluster loss: ensure backend is intact, rerun `terragrunt apply --all`, let ArgoCD restore from Git and ExternalSecrets sync secrets, then verify pods and `argocd app list`.
