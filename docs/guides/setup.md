# Setup Guide

Steps to get a dev environment running and deploy the first csoc stack.

## Prerequisites

Required: Git ≥2.30, Docker (4GB+ RAM), VS Code with Remote Containers, and access to AWS/Azure/GCP. Host CLIs (aws/az/gcloud) help with authentication but are optional.

## Step 1: Clone Repository

```bash
git clone https://github.com/indiana-university/gen3-kro.git
cd gen3-kro
```

## Step 2: Launch Development Container

Open the repo with VS Code → **Reopen in Container** when prompted. The devcontainer includes Terraform, Terragrunt, kubectl, ArgoCD CLI, and cloud CLIs. Details: [`.devcontainer/README.md`](../.devcontainer/README.md).

## Step 3: Configure Cloud Credentials

### AWS

Configure credentials on the host; the devcontainer mounts them automatically.

AWS example:
```bash
aws configure --profile gen3-dev
aws sts get-caller-identity --profile gen3-dev
```

### Azure

Azure:
```bash
az login
az account set --subscription <subscription-id>
```

### GCP

GCP:
```bash
gcloud auth login
gcloud config set project <project-id>
```

## Step 4: Create Terraform State Backend

Create a Terraform state backend.

AWS (S3 + DynamoDB):
```bash
aws s3 mb s3://gen3-terraform-state-dev --region us-east-1 --profile gen3-dev
aws dynamodb create-table \
  --table-name gen3-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1 --profile gen3-dev
```

Azure (Storage + container):
```bash
az group create --name gen3-terraform-rg --location eastus
az storage account create --name gen3tfstate --resource-group gen3-terraform-rg --location eastus --sku Standard_LRS
az storage container create --name tfstate --account-name gen3tfstate
```

GCP (GCS with versioning):
```bash
gsutil mb -l us-central1 gs://gen3-terraform-state-dev
gsutil versioning set on gs://gen3-terraform-state-dev
```

## Step 5: Configure Environment Secrets

Navigate to your environment directory and create secrets configuration:

```bash
cd live/aws/us-east-1/gen3-kro-dev
cp secrets-example.yaml secrets.yaml
```

Edit `secrets.yaml` with your configuration. Minimum required fields:

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
    org_name: indiana-university           # Your GitHub organization
    repo_name: gen3-kro         # Your repository name
    github_url: github.com
    branch: main
    bootstrap_path: argocd/bootstrap

backend:
  terraform_locks_table: gen3-terraform-locks  # From Step 4

spokes: []  # Empty for hub-only deployment
```

See `live/README.md` for the full schema.

## Step 6: Plan Infrastructure Deployment

Preview changes:
```bash
cd live/aws/us-east-1/gen3-kro-dev
terragrunt plan --all 2>&1 | tee plan.log
```
Confirm resource names match `secrets.yaml` and no surprise destroys.

## Step 7: Deploy Infrastructure

Apply the Terragrunt stack:

```bash
terragrunt apply --all 2>&1 | tee apply.log
```

When prompted, review the plan summary and type `yes` to confirm.

Typical duration: 15–25 minutes for VPC, EKS, node groups, and ArgoCD/bootstrap ApplicationSets.

## Step 8: Connect to Cluster

After deployment completes, configure kubectl and ArgoCD CLI access:

```bash
cd /workspaces/gen3-kro  # Repository root
./scripts/connect-cluster.sh
```

The script updates kubeconfig, fetches ArgoCD credentials/URL, and logs in. Verify:
```bash
kubectl get nodes
kubectl get pods -n argocd
argocd app list
```

## Step 9: Verify ArgoCD Bootstrap

Check ApplicationSets and a target addon:
```bash
kubectl get applicationset -n argocd
argocd app list
argocd app get csoc-addons-kro
```

## Step 10: Access ArgoCD UI (Optional)

Port-forward ArgoCD server to access web UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open `https://localhost:8080` and use the admin password from `connect-cluster.sh` (also `outputs/argo/admin-password.txt`).

## Next Steps

After deployment: explore ArgoCD, deploy Gen3 services via KRO graph instances, configure ExternalSecrets, add spokes in `secrets.yaml`, and see `customization.md` and `operations.md`.

## Troubleshooting

### Container Build Failures

Devcontainer fails: increase Docker memory, ensure daemon running, and rebuild the container.

### Terragrunt Plan Errors

Terragrunt backend errors: verify backend exists, credentials work, and `secrets.yaml` points to the right backend.

### EKS Cluster Creation Timeout

EKS create timeout: check AWS status, IAM permissions, and CloudFormation events.

### kubectl Connection Refused

`kubectl` connection refused: rerun `./scripts/connect-cluster.sh`, or `aws eks update-kubeconfig`, and confirm endpoint access.

### ArgoCD Applications Not Appearing

ArgoCD apps missing: check ApplicationSet status, cluster secret presence, and controller logs.

More help: `../live/aws/us-east-1/gen3-kro-dev/README.md` and `operations.md`.
