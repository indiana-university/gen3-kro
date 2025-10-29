# gen3-kro-dev Environment (AWS us-east-1)

Development environment for Gen3-KRO platform deployed to AWS us-east-1 region.

## Overview

This environment provisions:
- **VPC**: `10.0.0.0/16` with public and private subnets across 2 availability zones
- **EKS Cluster**: Kubernetes 1.33 with managed node groups
- **ArgoCD**: GitOps controller managing platform addons
- **KRO**: Kubernetes Resource Orchestrator for declarative infrastructure
- **ACK Controllers**: AWS Controllers for Kubernetes (S3, RDS, etc.)
- **Pod Identity Roles**: IAM roles for workload authentication

## Prerequisites

### AWS Account Setup

Before deploying this environment, complete the setup steps in [`docs/guides/setup.md`](../../../../docs/guides/setup.md#step-3-configure-cloud-credentials):

1. **AWS CLI configured** with `gen3-dev` profile
2. **IAM permissions** for VPC, EKS, IAM, S3, and DynamoDB operations
3. **Terraform state backend** (S3 bucket and DynamoDB table)

See [`docs/guides/setup.md`](../../../../docs/guides/setup.md#step-4-create-terraform-state-backend) for detailed backend setup instructions.

### Secrets Configuration

Create `secrets.yaml` from template:

```bash
cd live/aws/us-east-1/gen3-kro-dev
cp secrets-example.yaml secrets.yaml
# Edit secrets.yaml with your AWS account details
```

**Key required fields:**
- `csoc.provider.profile`: AWS CLI profile name (e.g., `iu-uits-rds-gen3`)
- `csoc.provider.terraform_state_bucket`: S3 bucket for Terraform state
- `csoc.gitops.repo_name`: GitHub repository details

See [`../README.md`](../README.md#secretsyaml-schema) for complete `secrets.yaml` schema and examples.

## Deployment

For initial deployment workflow, see [`docs/guides/setup.md`](../../../../docs/guides/setup.md). For day-to-day operations and infrastructure changes, see [`docs/guides/operations.md`](../../../../docs/guides/operations.md).

### Plan Infrastructure

```bash
cd live/aws/us-east-1/gen3-kro-dev
terragrunt plan --all 2>&1 | tee plan.log
```

See [`docs/guides/operations.md`](../../../../docs/guides/operations.md#planning-and-applying-infrastructure-changes) for detailed planning guidance.

### Apply Infrastructure

```bash
terragrunt apply --all 2>&1 | tee apply.log
```

Expected duration: 15-25 minutes (EKS cluster creation is the longest step).

### Connect to Cluster

After deployment, configure kubectl and ArgoCD CLI:

```bash
./scripts/connect-cluster.sh
```

See [`scripts/README.md`](../../../../scripts/README.md#connect-clustersh) for script details. Verify connectivity:

```bash
kubectl get nodes
argocd app list
```

## Stack Commands

### View Outputs

```bash
terragrunt output --all
```

Key outputs:
- `cluster_name`: EKS cluster identifier
- `cluster_endpoint`: Kubernetes API server URL
- `argocd_server_endpoint`: ArgoCD UI URL (access via `kubectl port-forward`)
- `inline_policy`: Boolean to show if inline policy is attached
- `pod_identity_role_arns`: IAM role ARNs for addons

### Validate Configuration

```bash
terragrunt validate --all
```

Checks Terraform syntax and configuration validity without applying changes.

### Refresh State

Sync Terraform state with actual AWS resources:

```bash
terragrunt refresh --all
```

### Destroy Environment

**Warning: Destructive operation. All resources will be deleted.**

```bash
terragrunt destroy --all 2>&1 | tee destroy.log
```

Pre-destroy checklist:
- [ ] Backup critical data (database snapshots, S3 bucket contents)
- [ ] Confirm no production workloads are running
- [ ] Review destroy plan before confirming

## Log Locations

All logs are written to the environment directory (gitignored):

| File | Purpose |
|------|---------|
| `plan.log` | Output from `terragrunt plan --all` |
| `apply.log` | Output from `terragrunt apply --all` |
| `destroy.log` | Output from `terragrunt destroy --all` |
| `output.log` | Extracted Terragrunt outputs |

Repository-wide logs:
- `outputs/logs/terragrunt-*.log`: Timestamped Terragrunt operations when running `./init.sh`
- `outputs/logs/connect-cluster-*.log`: Cluster connection logs when running `./scripts/connect-cluster.sh` and `./init.sh`

## Troubleshooting

### EKS Cluster Access Denied

**Symptom:** `kubectl get nodes` returns "Unauthorized" or "Access Denied"

**Solution:**
```bash
# Re-run cluster connection script
./scripts/connect-cluster.sh

# Verify AWS profile is active
aws sts get-caller-identity --profile gen3-kro-dev

# Update kubeconfig manually
aws eks update-kubeconfig --name gen3-kro-dev --region us-east-1 --profile gen3-kro-dev
```

### Terragrunt State Lock Errors

**Symptom:** `Error acquiring the state lock`

**Solution:**
```bash
# List locks in DynamoDB
aws dynamodb scan --table-name gen3-terraform-locks

# Force unlock (if safe to do so)
terragrunt force-unlock <lock-id>
```

### ArgoCD Applications Not Syncing

**Symptom:** Applications stuck in "OutOfSync" or "Unknown" status

**Solution:**
```bash
# Check ArgoCD controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Manually sync application
argocd app sync <app-name>

# Verify git repository connectivity
argocd repo list
```

### Pod Identity Role Not Assumed

**Symptom:** Addon pods cannot access AWS services (S3)

**Solution:**
```bash
# Verify Pod Identity association exists
aws eks list-pod-identity-associations --cluster-name gen3-kro-dev

# Check pod service account annotations
kubectl get sa -n ack-system ack-s3 -o yaml | grep eks.amazonaws.com/role-arn

# Review IAM role trust policy
aws iam get-role --role-name csoc-ack-s3
```

See [`docs/guides/operations.md`](../../../../docs/guides/operations.md) for comprehensive troubleshooting guides.

## Environment-Specific Notes

- **VPC CIDR**: `10.0.0.0/16` - ensure no conflicts with existing AWS resources
- **Node Instance Type**: we use eks-auto see `cluster_compute_config`
- **NAT Gateway**: Single NAT gateway (cost optimization for dev) - set `single_nat_gateway: false` for high availability

---
**Last updated:** 2025-10-28
