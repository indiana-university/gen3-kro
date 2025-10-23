# Adding Cluster Addons

This guide explains how to add and configure cluster addons using ArgoCD and the Gen3 KRO platform.

## Overview

Cluster addons are platform services deployed via ArgoCD ApplicationSets. The system supports two types:

- **ACK Controllers**: AWS Controllers for Kubernetes (manage AWS resources)
- **Platform Addons**: Supporting services (External Secrets, Kyverno, metrics, etc.)

## Quick Start

### Add ACK Controller

1. **Add to catalog** (`argocd/hub/addons/catalog.yaml`):
```yaml
- addon: s3
  repoURL: oci://public.ecr.aws/aws-controllers-k8s/s3-chart
  revision: v1.0.11
  chartPath: s3-chart
```

2. **Enable in hub** (`argocd/hub/addons/enablement.yaml`):
```yaml
s3:
  enabled: true
```

3. **Configure values** (`argocd/hub/addons/values.yaml`):
```yaml
global:
  roleArns:
    s3: "arn:aws:iam::123456789012:role/hub-ack-s3"

values:
  s3:
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: "{{.Values.global.roleArns.s3}}"
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
```

4. **Create IAM policy** (`iam/gen3/csoc/acks/s3/internal-policy.json`):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": "*"
    }
  ]
}
```

5. **Update Terraform** to create pod identity for S3:

Edit `live/aws/us-east-1/gen3-kro-hub/terragrunt.hcl`:
```hcl
ack_configs = {
  # ... existing ...
  s3 = {
    enable_pod_identity = true
    namespace           = "ack-system"
    service_account     = "ack-s3-sa"
  }
}
```

6. **Deploy**:
```bash
cd live/aws/us-east-1/gen3-kro-hub
terragrunt apply

# Verify in ArgoCD
kubectl get application hub-s3 -n argocd
kubectl get pods -n ack-system -l app.kubernetes.io/name=s3-chart
```

## Available ACK Controllers

| Controller | Purpose | Chart Version |
|------------|---------|---------------|
| cloudtrail | CloudTrail logs | v1.0.5 |
| cloudwatchlogs | CloudWatch logs | v1.0.9 |
| ec2 | EC2 instances, VPCs, security groups | v1.7.0 |
| efs | Elastic File System | v1.1.1 |
| eks | EKS clusters | v1.9.3 |
| iam | IAM roles, policies | v1.2.1 |
| kms | KMS keys | v1.0.8 |
| opensearchservice | OpenSearch domains | v1.0.7 |
| rds | RDS databases | v1.5.0 |
| route53 | DNS records | v1.0.8 |
| s3 | S3 buckets | v1.0.11 |
| secretsmanager | Secrets Manager secrets | v1.0.3 |
| sns | SNS topics | v1.0.10 |
| sqs | SQS queues | v1.0.12 |
| wafv2 | WAF rules | v1.0.5 |

## Available Platform Addons

| Addon | Purpose | Chart Repo |
|-------|---------|------------|
| kro | Kubernetes Resource Orchestrator | https://kro-run.github.io/kro |
| external-secrets | Secret management | https://charts.external-secrets.io |
| kyverno | Policy engine | https://kyverno.github.io/kyverno |
| metrics-server | Resource metrics | https://kubernetes-sigs.github.io/metrics-server |
| kube-state-metrics | Cluster metrics | https://prometheus-community.github.io/helm-charts |

## Configuration Files

### catalog.yaml

Defines addon metadata: Helm chart location, version, and name.

**Structure**:
```yaml
items:
  - addon: <addon-name>
    repoURL: <helm-repo-url>
    revision: <chart-version>
    chartPath: <chart-name>
```

**Example**:
```yaml
items:
  - addon: rds
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/rds-chart
    revision: v1.5.0
    chartPath: rds-chart
  - addon: external-secrets
    repoURL: https://charts.external-secrets.io
    revision: 0.9.13
    chartPath: external-secrets
```

### enablement.yaml

Controls which addons are deployed per cluster.

**Structure**:
```yaml
cluster: <cluster-name>
enablement:
  <addon-name>:
    enabled: <true|false>
```

**Example**:
```yaml
cluster: hub
enablement:
  rds:
    enabled: true
  external-secrets:
    enabled: true
  kro:
    enabled: true  # Hub only
```

### values.yaml

Provides Helm chart values for each addon.

**Structure**:
```yaml
global:
  roleArns:
    <addon-name>: <iam-role-arn>
  namespaces:
    ack: "ack-system"

values:
  <addon-name>:
    <helm-value-key>: <value>
```

**Example**:
```yaml
global:
  roleArns:
    rds: "arn:aws:iam::123456789012:role/hub-ack-rds"

values:
  rds:
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: "{{.Values.global.roleArns.rds}}"
    aws:
      region: us-east-1
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
```

## Spoke-Specific Configuration

Spokes can override hub defaults by creating their own addon files.

### Directory Structure

```
argocd/spokes/<spoke-name>/addons/
├── catalog.yaml        # Optional: Override chart versions
├── enablement.yaml     # Which addons to deploy
└── values.yaml         # Spoke-specific values
```

### Example: Spoke1 Enablement

```yaml
cluster: spoke1
enablement:
  ec2:
    enabled: true
  rds:
    enabled: true
  s3:
    enabled: true
  eks:
    enabled: false  # Spokes don't need EKS controller
  kro:
    enabled: false  # KRO only on hub
```

### Example: Spoke1 Values

```yaml
global:
  roleArns:
    ec2: "arn:aws:iam::987654321098:role/spoke1-ec2"
    rds: "arn:aws:iam::987654321098:role/spoke1-rds"
    s3: "arn:aws:iam::987654321098:role/spoke1-s3"

values:
  ec2:
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: "{{.Values.global.roleArns.ec2}}"
  rds:
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: "{{.Values.global.roleArns.rds}}"
```

## IAM Policy Management

### Policy Directory Structure

```
iam/gen3/<context>/<service-type>/<service-name>/
├── internal-policy.json          # Main policy
├── override-policy-*.json        # Additional policies
└── managed-policy-arns.txt       # AWS managed policies
```

### Example: RDS Policy

**internal-policy.json**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:Describe*",
        "rds:List*",
        "rds:CreateDBInstance",
        "rds:DeleteDBInstance",
        "rds:ModifyDBInstance",
        "rds:AddTagsToResource",
        "rds:RemoveTagsFromResource"
      ],
      "Resource": "*"
    }
  ]
}
```

**override-policy-secrets.json** (additional permissions):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:rds/*"
    }
  ]
}
```

**managed-policy-arns.txt**:
```
arn:aws:iam::aws:policy/AmazonRDSReadOnlyAccess
```

## Terraform Pod Identity Configuration

Update Terragrunt to create pod identities for new addons.

### Hub Configuration

Edit `live/aws/us-east-1/gen3-kro-hub/terragrunt.hcl`:

```hcl
inputs = {
  # ACK Controllers
  ack_configs = {
    # Existing controllers...
    rds = {
      enable_pod_identity = true
      namespace           = "ack-system"
      service_account     = "ack-rds-sa"
    }
    s3 = {
      enable_pod_identity = true
      namespace           = "ack-system"
      service_account     = "ack-s3-sa"
    }
  }

  # Platform Addons
  addon_configs = {
    external-secrets = {
      enable_pod_identity = true
      namespace           = "external-secrets-system"
      service_account     = "external-secrets"
    }
  }
}
```

### Spoke Configuration

Edit `live/aws/us-east-1/spoke1-iam/terragrunt.hcl`:

```hcl
dependency "hub" {
  config_path = "../gen3-kro-hub"
}

inputs = {
  ack_configs = {
    rds = {
      hub_role_arn    = dependency.hub.outputs.ack_role_arns["rds"]
      override_arn    = ""  # Create role
      namespace       = "ack-system"
      service_account = "ack-rds-sa"
    }
    s3 = {
      hub_role_arn    = dependency.hub.outputs.ack_role_arns["s3"]
      override_arn    = ""
      namespace       = "ack-system"
      service_account = "ack-s3-sa"
    }
  }
}
```

## Deployment Process

### 1. Update Git Configuration

```bash
cd /workspaces/gen3-kro

# Add addon to catalog
vim argocd/hub/addons/catalog.yaml

# Enable addon
vim argocd/hub/addons/enablement.yaml

# Configure values
vim argocd/hub/addons/values.yaml

# Commit changes
git add argocd/hub/addons/
git commit -m "Add S3 ACK controller"
```

### 2. Create IAM Policies

```bash
mkdir -p iam/gen3/csoc/acks/s3
cat > iam/gen3/csoc/acks/s3/internal-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": "*"
    }
  ]
}
EOF

git add iam/gen3/csoc/acks/s3/
git commit -m "Add S3 IAM policy for hub"
```

### 3. Update Terraform

```bash
cd live/aws/us-east-1/gen3-kro-hub

# Edit terragrunt.hcl to add s3 to ack_configs

terragrunt apply
```

### 4. Push to Git (Triggers ArgoCD)

```bash
git push origin main
```

### 5. Verify Deployment

```bash
# Check ArgoCD application
kubectl get application hub-s3 -n argocd

# Check pod
kubectl get pods -n ack-system -l app.kubernetes.io/name=s3-chart

# Check service account
kubectl describe sa ack-s3-sa -n ack-system
# Verify eks.amazonaws.com/role-arn annotation

# Test S3 controller
kubectl apply -f - <<EOF
apiVersion: s3.services.k8s.aws/v1alpha1
kind: Bucket
metadata:
  name: test-bucket-123456
spec:
  name: test-bucket-123456
EOF

kubectl get bucket test-bucket-123456
```

## Updating Addon Versions

### Update Chart Version

Edit `argocd/hub/addons/catalog.yaml`:

```yaml
- addon: ec2
  repoURL: oci://public.ecr.aws/aws-controllers-k8s/ec2-chart
  revision: v1.8.0  # Updated from v1.7.0
  chartPath: ec2-chart
```

Commit and push:

```bash
git add argocd/hub/addons/catalog.yaml
git commit -m "Update EC2 ACK controller to v1.8.0"
git push
```

ArgoCD detects the change and upgrades the controller.

## Disabling Addons

### Hub

Edit `argocd/hub/addons/enablement.yaml`:

```yaml
s3:
  enabled: false  # Disable S3 controller
```

Commit and push. ArgoCD will delete the application.

### Spoke

Edit `argocd/spokes/spoke1/addons/enablement.yaml`:

```yaml
rds:
  enabled: false
```

Commit and push.

## Troubleshooting

### Addon Not Deploying

**Check ApplicationSet**:
```bash
kubectl get applicationset hub-addons -n argocd -o yaml
kubectl get applicationset spoke-addons -n argocd -o yaml
```

Look for generator errors in `status.conditions`.

**Check Application**:
```bash
kubectl get application hub-<addon> -n argocd -o yaml
```

Check `status.sync.status` and `status.health.status`.

### Pod Identity Not Working

**Check Service Account**:
```bash
kubectl describe sa <service-account> -n <namespace>
```

Verify `eks.amazonaws.com/role-arn` annotation is present.

**Check IAM Role**:
```bash
aws iam get-role --role-name <cluster-name>-<addon-name>
```

Verify trust policy and attached policies.

### Controller Logs Show Permission Errors

**Check IAM Policy**:
```bash
aws iam get-role-policy --role-name <cluster-name>-<addon-name> --policy-name <policy-name>
```

Update IAM policy JSON file and run `terragrunt apply`.

## See Also

- [ArgoCD Configuration](../argocd/README.md)
- [Terragrunt Deployment Guide](./setup-terragrunt.md)
- [Hub Combination](../terraform/combinations/hub/README.md)
- [ACK Documentation](https://aws-controllers-k8s.github.io/community/)
