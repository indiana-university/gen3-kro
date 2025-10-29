# Setup Guide

Step-by-step instructions for setting up the Gen3-KRO development environment and deploying your first infrastructure stack.

## Prerequisites

Before starting, ensure you have:

- **Git**: Version 2.30+ installed
- **Docker Desktop**: 4.0+ with at least 4GB RAM allocated (8GB recommended for better performance)
- **VS Code**: Latest version with Remote - Containers extension
- **Cloud provider account**: AWS, Azure, or GCP with appropriate permissions
- **Cloud CLI installed on host** (optional but recommended):
  - AWS CLI v2
  - Azure CLI
  - Google Cloud SDK

## Step 1: Clone Repository

```bash
git clone https://github.com/indiana-university/gen3-kro.git
cd gen3-kro
```

## Step 2: Launch Development Container

### Using VS Code

1. Open repository in VS Code:
   ```bash
   code .
   ```

2. VS Code will detect `.devcontainer/devcontainer.json` and prompt:
   ```
   Folder contains a Dev Container configuration file.
   Reopen in Container?
   ```

3. Click **Reopen in Container**

4. Wait for container build and extension installation (3-5 minutes on first run)

5. Verify tools are available:
   ```bash
   terraform version    # Should show >= 1.5.0
   terragrunt version   # Should show >= 0.66.0
   kubectl version --client
   argocd version --client
   ```

See [`.devcontainer/README.md`](../.devcontainer/README.md) for detailed container configuration, tool inventory, environment variables, and credential mounting.

## Step 3: Configure Cloud Credentials

### AWS

Ensure AWS credentials are configured on your host machine:

```bash
# On host (outside container)
aws configure --profile gen3-dev
# Enter AWS Access Key ID, Secret Access Key, Region
```

The devcontainer mounts `~/.aws/` from host, making credentials available inside the container.

Verify inside container:
```bash
aws sts get-caller-identity --profile gen3-dev
```

### Azure

Login to Azure CLI on host:

```bash
# On host
az login
az account set --subscription <subscription-id>
```

Credentials are cached in `~/.azure/` and mounted into container.

Verify inside container:
```bash
az account show
```

### GCP

Authenticate gcloud CLI on host:

```bash
# On host
gcloud auth login
gcloud config set project <project-id>
```

Credentials stored in `~/.config/gcloud/` are mounted into container.

Verify inside container:
```bash
gcloud auth list
gcloud config get-value project
```

## Step 4: Create Terraform State Backend

Before deploying infrastructure, create a backend for Terraform state storage.

### AWS (S3 + DynamoDB)

```bash
# Inside devcontainer
aws s3 mb s3://gen3-terraform-state-dev --region us-east-1 --profile gen3-dev

aws dynamodb create-table \
  --table-name gen3-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1 \
  --profile gen3-dev
```

### Azure (Storage Account + Container)

```bash
# Inside devcontainer
RESOURCE_GROUP="gen3-terraform-rg"
STORAGE_ACCOUNT="gen3tfstate"
CONTAINER="tfstate"
LOCATION="eastus"

az group create --name $RESOURCE_GROUP --location $LOCATION
az storage account create --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --location $LOCATION --sku Standard_LRS
az storage container create --name $CONTAINER --account-name $STORAGE_ACCOUNT
```

### GCP (Cloud Storage Bucket)

```bash
# Inside devcontainer
gsutil mb -l us-central1 gs://gen3-terraform-state-dev
gsutil versioning set on gs://gen3-terraform-state-dev
```

## Step 5: Configure Environment Secrets

Navigate to your environment directory and create secrets configuration:

```bash
cd live/aws/us-east-1/gen3-kro-dev
cp secrets-example.yaml secrets.yaml
```

Edit `secrets.yaml` with your configuration. **Minimum required fields:**

```yaml
csoc:
  alias: csoc
  cluster_name: gen3-hub-dev
  provider:
    name: aws
    region: us-east-1
    profile: gen3-dev
    terraform_state_bucket: gen3-terraform-state-dev  # From Step 4

  vpc:
    enable_vpc: true
    vpc_name: gen3-hub-vpc
    vpc_cidr: 10.0.0.0/16
    enable_nat_gateway: true
    single_nat_gateway: true
    availability_zones:
      - us-east-1a
      - us-east-1b
    private_subnet_cidrs:
      - 10.0.1.0/24
      - 10.0.2.0/24
    public_subnet_cidrs:
      - 10.0.101.0/24
      - 10.0.102.0/24

  k8s_cluster:
    enable_cluster: true
    kubernetes_version: "1.33"
    cluster_endpoint_public_access: true
    enable_cluster_creator_admin_permissions: true

  addon_configs:
    ack-s3:
      namespace: ack-system
      create_namespace: true

  gitops:
    org_name: uc-cdis           # Your GitHub organization
    repo_name: gen3-kro         # Your repository name
    github_url: github.com
    branch: main
    bootstrap_path: argocd/bootstrap

backend:
  terraform_locks_table: gen3-terraform-locks  # From Step 4

spokes: []  # Empty for hub-only deployment
```

See [`live/README.md`](../live/README.md) for complete schema reference.

## Step 6: Plan Infrastructure Deployment

Preview infrastructure changes without applying them:

```bash
cd live/aws/us-east-1/gen3-kro-dev
terragrunt plan --all 2>&1 | tee plan.log
```

Review plan output carefully:
- **Resources to add**: VPC, subnets, NAT gateways, EKS cluster, IAM roles, ArgoCD
- **No unexpected deletions or replacements**
- **Correct resource naming** (cluster name, VPC name match `secrets.yaml`)

Expected resource count: ~50-80 resources (depending on addon configuration)

## Step 7: Deploy Infrastructure

Apply the Terragrunt stack:

```bash
terragrunt apply --all 2>&1 | tee apply.log
```

When prompted, review the plan summary and type `yes` to confirm.

**Expected duration:** 15-25 minutes
- VPC creation: 1-2 minutes
- EKS cluster creation: 10-15 minutes
- Node group creation: 5-8 minutes
- ArgoCD installation: 2-3 minutes

**Deployment phases:**
1. VPC and networking resources
2. EKS cluster control plane
3. EKS managed node groups
4. IAM roles for Pod Identity
5. ArgoCD Helm chart installation
6. Bootstrap ApplicationSets deployment

## Step 8: Connect to Cluster

After deployment completes, configure kubectl and ArgoCD CLI access:

```bash
cd /workspaces/gen3-kro  # Repository root
./scripts/connect-cluster.sh
```

This script:
1. Extracts cluster name and region from Terragrunt outputs
2. Updates `~/.kube/config` with cluster credentials
3. Retrieves ArgoCD admin password from `outputs/argo/admin-password.txt`
4. Logs in to ArgoCD CLI

Verify connectivity:
```bash
kubectl get nodes
# Should show 2-3 nodes in Ready state

kubectl get pods -n argocd
# Should show ArgoCD components running

argocd app list
# Should show csoc-addons ApplicationSet applications
```

## Step 9: Verify ArgoCD Bootstrap

Check ArgoCD ApplicationSets and Applications:

```bash
# List ApplicationSets
kubectl get applicationset -n argocd

# List Applications
argocd app list

# Check specific addon status
argocd app get csoc-addons-kro
```

Expected ApplicationSets:
- `csoc-addons`: Hub cluster addons (KRO, ACK controllers)
- `graphs`: KRO ResourceGraphDefinitions

Expected Applications (from csoc-addons):
- `csoc-addons-kro`
- `csoc-addons-ack-s3` (if enabled in `secrets.yaml`)
- `csoc-addons-external-secrets` (if enabled)

## Step 10: Access ArgoCD UI (Optional)

Port-forward ArgoCD server to access web UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open browser to: `https://localhost:8080`

**Login credentials:**
- Username: `admin`
- Password: Retrieved by `connect-cluster.sh` (also in `outputs/argo/admin-password.txt`)

## Next Steps

After successful deployment:

- **Explore ArgoCD**: Review deployed applications and sync status
- **Deploy Gen3 services**: Create KRO graph instances for Gen3 workloads
- **Configure secrets**: Set up ExternalSecrets operator to sync cloud secrets
- **Add spoke environments**: Extend `secrets.yaml` with spoke configurations
- **Review customization options**: See [`customization.md`](customization.md)
- **Learn day-2 operations**: See [`operations.md`](operations.md)

## Troubleshooting

### Container Build Failures

**Symptom:** Devcontainer fails to build

**Solutions:**
- Increase Docker memory allocation (4GB minimum)
- Check Docker daemon is running: `docker ps`
- Rebuild container: VS Code → Command Palette → `Remote-Containers: Rebuild Container`

### Terragrunt Plan Errors

**Symptom:** `terragrunt plan --all` fails with backend errors

**Solutions:**
- Verify state backend exists (S3 bucket, DynamoDB table)
- Check AWS credentials are valid: `aws sts get-caller-identity --profile gen3-dev`
- Ensure `secrets.yaml` specifies correct backend configuration

### EKS Cluster Creation Timeout

**Symptom:** `terraform apply` times out waiting for EKS cluster

**Solutions:**
- Check AWS service health: https://status.aws.amazon.com/
- Verify IAM permissions for `eks:CreateCluster`
- Review CloudFormation stack events in AWS Console (EKS uses CloudFormation internally)

### kubectl Connection Refused

**Symptom:** `kubectl get nodes` returns "connection refused"

**Solutions:**
- Re-run `./scripts/connect-cluster.sh`
- Manually update kubeconfig: `aws eks update-kubeconfig --name gen3-hub-dev --region us-east-1 --profile gen3-dev`
- Verify cluster endpoint is accessible (check security groups if private endpoint)

### ArgoCD Applications Not Appearing

**Symptom:** `argocd app list` shows no applications

**Solutions:**
- Check ApplicationSet status: `kubectl describe applicationset csoc-addons -n argocd`
- Verify cluster secret exists: `kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster`
- Review ArgoCD application-controller logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller`

For additional troubleshooting, see:
- [gen3-kro-dev environment-specific runbook](../live/aws/us-east-1/gen3-kro-dev/README.md)
- [Operations guide](operations.md)

---
**Last updated:** 2025-10-26
