# Operations Guide

Day-to-day operational workflows for managing Gen3-KRO infrastructure, including planning/applying changes, syncing ArgoCD applications, rotating credentials, and troubleshooting common issues.

## Daily Operations Checklist

### Monitor Infrastructure Health

```bash
# Check Kubernetes cluster status
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running

# Check ArgoCD application health
argocd app list
argocd app get <app_name> --refresh

# Check Terraform state drift
cd live/<provider>/<region>/<csoc_alias>
terragrunt plan --all --terragrunt-non-interactive
```

### Review Logs

```bash
# Terragrunt operation logs
./outputs/logs/terragrunt-*.log

# ArgoCD application controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f

# Application-specific logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=<app_name>
```

## Planning and Applying Infrastructure Changes

### Plan Changes

Before applying any modifications, preview changes with Terragrunt plan:

```bash
cd live/<provider>/<region>/<csoc_alias>
terragrunt plan --all 2>&1 | tee outputs/logs/plan-$(date +%Y%m%d-%H%M%S).log
```

**Review plan output for:**
- Number of resources to add/change/destroy
- Specific resource modifications (check for unexpected changes)
- Dependency ordering (ensure no circular dependencies)

**Common plan scenarios:**

| Change Type | Expected Plan Output |
|-------------|----------------------|
| Add new addon to `secrets.yaml` | New IAM role, new ArgoCD Application |
| Modify VPC CIDR | VPC replacement (destroys cluster) |
| Change cluster node count | Node group update (in-place) |
| Update IAM policy | IAM role policy update (in-place) |

### Apply Changes

After reviewing plan:

```bash
terragrunt apply --all 2>&1 | tee outputs/logs/apply-$(date +%Y%m%d-%H%M%S).log
```

**Apply duration estimates** (approximate, may vary by environment and cloud provider):
- IAM policy updates: 1-2 minutes
- Node group scaling: 3-5 minutes
- Addon additions: 2-4 minutes
- Cluster version upgrade: 15-30 minutes

**Post-apply verification:**

```bash
# Verify Terraform outputs
terragrunt output --all

# Check cluster accessibility
kubectl get nodes

# Verify new resources
kubectl get pods -n <new-addon-namespace>
```

### Targeted Apply (Single Unit)

To apply changes to a specific Terragrunt unit (note: dependencies will still be processed):

```bash
cd live/<provider>/<region>/<csoc_alias>
terragrunt apply --terragrunt-include-dir units/csoc
```

## Syncing ArgoCD Applications

### Auto-Sync vs Manual Sync

**Auto-sync (disabled by default):** ArgoCD automatically applies Git changes to cluster

**Manual sync:** Operator reviews changes before applying

### Sync All Applications

```bash
# Sync all applications in csoc-addons ApplicationSet
argocd app sync -l argocd.argoproj.io/instance=csoc-addons

# Sync all graph applications
argocd app sync -l argocd.argoproj.io/instance=graphs
```

### Sync Specific Application

```bash
argocd app sync csoc-addons-kro
argocd app sync csoc-addons-ack-s3
```

### Force Refresh

If application shows stale status:

```bash
argocd app get csoc-addons-kro --refresh
argocd app sync csoc-addons-kro --prune --force
```

### Sync Waves

ArgoCD respects sync wave annotations for ordered deployment:

- **Wave -1**: KRO (must install first for ResourceGraphDefinitions)
- **Wave 0**: All other addons (parallel deployment)

Monitor sync wave progression:

```bash
argocd app get csoc-addons-kro -o yaml | grep sync-wave
kubectl get applications -n argocd -o json | jq '.items[] | {name: .metadata.name, wave: .metadata.annotations["argocd.argoproj.io/sync-wave"]}'
```

## Credential Rotation

### AWS Credentials

**Rotate IAM access keys:**

1. Create new access key in AWS Console or CLI
2. Update host `~/.aws/credentials` file
3. Restart devcontainer to mount new credentials
4. Verify new credentials work:
   ```bash
   aws sts get-caller-identity --profile gen3-dev
   ```
5. Delete old access key

**Rotate Pod Identity roles:**

IAM roles for Pod Identity are managed by Terraform. No manual rotation required; roles use trust policies with OIDC provider.

### ArgoCD Admin Password

**Rotate ArgoCD password:**

```bash
# Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# Update ArgoCD admin password
argocd account update-password --current-password <current-password> --new-password $NEW_PASSWORD

# Update stored password
echo $NEW_PASSWORD > outputs/argo/admin-password.txt
```

### Kubernetes Service Account Tokens

Tokens auto-rotate by Kubernetes. For manual rotation:

```bash
kubectl delete secret -n <namespace> <service-account-token-secret>
kubectl get sa -n <namespace> <service-account> -o yaml
# New token auto-generated
```

## Troubleshooting

### Terraform State Drift

**Symptom:** `terragrunt plan` shows unexpected changes

**Diagnosis:**

```bash
cd live/aws/us-east-1/gen3-kro-dev
terragrunt plan --all --detailed-exitcode
# Exit code 2 = drift detected
```

**Resolution:**

1. **Review drift**: Check plan output for modified resources
2. **Manual changes**: If changes were made outside Terraform, decide to:
   - **Import**: `terragrunt import --all <resource-type> <resource-id>`
   - **Apply**: Let Terraform revert manual changes
3. **Apply plan**: `terragrunt apply --all`

**Common drift scenarios:**

| Resource | Cause | Resolution |
|----------|-------|------------|
| Security group rules | Manual AWS Console changes | Review plan, apply to revert |
| Node group size | Auto-scaling modified count | Update `secrets.yaml` desired size |
| IAM role policies | External policy attachment | Remove external policies, apply |

### ArgoCD Application Stuck

**Symptom:** Application shows "Progressing" or "Unknown" for >10 minutes

**Diagnosis:**

```bash
argocd app get csoc-addons-kro
kubectl describe application csoc-addons-kro -n argocd
```

**Resolution steps:**

1. **Refresh application**:
   ```bash
   argocd app get csoc-addons-kro --refresh
   ```

2. **Check resource health**:
   ```bash
   argocd app get csoc-addons-kro --show-operation
   kubectl get pods -n <namespace>
   ```

3. **Review controller logs**:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=200
   ```

4. **Force sync**:
   ```bash
   argocd app sync csoc-addons-kro --force --prune
   ```

5. **Delete and recreate** (last resort):
   ```bash
   argocd app delete csoc-addons-kro
   # ArgoCD ApplicationSet will recreate
   ```

### Pod Identity Authentication Failures

**Symptom:** Addon pods cannot access AWS services, logs show "AccessDenied" or "UnauthorizedOperation"

**Diagnosis:**

```bash
# Check Pod Identity association
aws eks list-pod-identity-associations --cluster-name gen3-hub-dev

# Verify service account annotation
kubectl get sa -n ack-system ack-s3 -o yaml | grep eks.amazonaws.com/role-arn

# Check IAM role exists
aws iam get-role --role-name csoc-ack-s3

# Review role policy
aws iam get-role-policy --role-name csoc-ack-s3 --policy-name inline-policy
```

**Resolution:**

1. **Verify IAM policy grants required permissions**:
   - Check `iam/aws/_default/ack-s3/policy.json` or environment-specific override
   - Ensure actions match addon requirements

2. **Re-apply Terraform to refresh Pod Identity**:
   ```bash
   cd live/aws/us-east-1/gen3-kro-dev
   terragrunt apply --all
   ```

3. **Restart addon pods** to pick up new role:
   ```bash
   kubectl rollout restart deployment -n ack-system ack-s3-controller
   ```

### State Lock Issues

**Symptom:** `Error acquiring the state lock: ConditionalCheckFailedException`

**Diagnosis:**

```bash
# Check DynamoDB lock table
aws dynamodb scan --table-name gen3-terraform-locks --region us-east-1
```

**Resolution:**

1. **Verify no active Terragrunt processes**:
   ```bash
   ps aux | grep terragrunt
   ```

2. **Force unlock** (if safe):
   ```bash
   cd live/aws/us-east-1/gen3-kro-dev
   terragrunt force-unlock <lock-id>
   ```

3. **Manual lock removal** (emergency):
   ```bash
   aws dynamodb delete-item --table-name gen3-terraform-locks \
     --key '{"LockID": {"S": "<lock-id>"}}' --region us-east-1
   ```

### Cluster Upgrade Failures

**Symptom:** EKS cluster version upgrade fails or rolls back

**Diagnosis:**

```bash
# Check cluster status
aws eks describe-cluster --name gen3-hub-dev --query 'cluster.status'

# Review CloudFormation events (EKS uses CFN internally)
aws cloudformation describe-stack-events \
  --stack-name eksctl-gen3-hub-dev-cluster \
  --max-items 50
```

**Resolution:**

1. **Review incompatible addons**: Some addons require specific Kubernetes versions
2. **Check node group compatibility**: Ensure node AMI supports target version
3. **Rollback**: If upgrade fails, Terraform will attempt automatic rollback
4. **Manual intervention**: Contact AWS support if cluster is stuck

### Checking Logs

**Terragrunt operation logs:**

```bash
# View logs
./outputs/logs/terragrunt-*.log

# Search for errors
grep -i error ./outputs/logs/terragrunt-*.log
```

**Environment-specific logs:**

```bash
cd live/aws/us-east-1/gen3-kro-dev
cat apply.log | grep -i error
cat plan.log | grep "Plan:"
```

**ArgoCD logs:**

```bash
# Application controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=500

# Repo server
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=200

# Server (UI/API)
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=200
```

## Backup and Recovery

### Backup Terraform State

Terraform state is stored in cloud provider backends (S3, Azure Storage, GCS) with versioning enabled.

**Manual backup:**

```bash
# AWS S3
aws s3 cp s3://gen3-terraform-state-dev/gen3-kro-dev/units/csoc/terraform.tfstate \
  ./backups/terraform.tfstate.$(date +%Y%m%d-%H%M%S)

# List state versions
aws s3api list-object-versions --bucket gen3-terraform-state-dev \
  --prefix gen3-kro-dev/units/csoc/terraform.tfstate
```

**Restore from backup:**

```bash
# Restore specific version (AWS S3)
aws s3api get-object --bucket gen3-terraform-state-dev \
  --key gen3-kro-dev/units/csoc/terraform.tfstate \
  --version-id <version-id> \
  terraform.tfstate
```

### Backup ArgoCD Applications

ArgoCD application definitions are stored in Git (GitOps pattern), so Git repository serves as backup.

**Export application manifests:**

```bash
argocd app get csoc-addons-kro -o yaml > backups/csoc-addons-kro.yaml
kubectl get applications -n argocd -o yaml > backups/all-applications.yaml
```

### Disaster Recovery

**Scenario: Complete cluster loss**

1. **Restore Terraform state** from backend (automatic if backend intact)
2. **Re-run Terragrunt**:
   ```bash
   cd live/aws/us-east-1/gen3-kro-dev
   terragrunt apply --all
   ```
3. **ArgoCD automatically restores** applications from Git repository
4. **ExternalSecrets syncs** secrets from cloud secret managers
5. **Verify application health**:
   ```bash
   kubectl get pods --all-namespaces
   argocd app list
   ```

**Recovery time estimate:** 20-40 minutes (depending on cluster size)

---
**Last updated:** 2025-10-28
