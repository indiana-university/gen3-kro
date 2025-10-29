# Customization Guide

Workflows for customizing Gen3-KRO infrastructure, including module modifications, IAM policy adjustments, ArgoCD addon configuration, and KRO graph extensions.

## Overview

Gen3-KRO is designed for extensibility through layered customization:

1. **Environment-level**: Modify `live/<provider>/<region>/<csoc_alias>/secrets.yaml` for environment-specific settings (cluster size, VPC CIDR, enabled addons)
2. **IAM-level**: Override IAM policies in `iam/<provider>/<csoc_alias>/csoc/<addon_name>/inline-policy.json` for csoc or `iam/<provider>/<csoc_alias>/<spoke_alias>/<addon_name>/inline-policy.json` for spokes
3. **Module-level**: Extend or modify Terraform modules in `terraform/catalog/modules/` for infrastructure changes
4. **Combination-level**: Add resources to `terraform/catalog/combinations/` for composed patterns
5. **ArgoCD-level**: Adjust addon catalogs, enablement, and values in `argocd/addons/`
6. **KRO-level**: Create or modify ResourceGraphDefinitions in `argocd/graphs/`

## Customizing Infrastructure via secrets.yaml

The most common customization is adjusting environment configuration in `secrets.yaml`.

### Change Cluster Size

Edit `secrets.yaml` to modify node group configuration:

```yaml
csoc:
  k8s_cluster:
    cluster_compute_config:
      default:
        instance_types: ["t3.large"]  # Changed from t3.medium
        desired_size: 4                # Changed from 2
        min_size: 2
        max_size: 8
```

Apply changes:
```bash
cd live/<provider>/<region>/<csoc_alias>
terragrunt plan --all  # Review changes
terragrunt apply --all
```

### Adjust VPC Configuration

Change VPC CIDR or subnet layout:

```yaml
csoc:
  vpc:
    vpc_cidr: 10.100.0.0/16  # Changed from 10.0.0.0/16
    availability_zones:
      - us-east-1a
      - us-east-1b
      - us-east-1c  # Added third AZ
    private_subnet_cidrs:
      - 10.100.1.0/24
      - 10.100.2.0/24
      - 10.100.3.0/24  # Added third subnet
    public_subnet_cidrs:
      - 10.100.101.0/24
      - 10.100.102.0/24
      - 10.100.103.0/24
```

**Warning:** Changing VPC CIDR requires VPC recreation (destroys cluster and all data/workloads). For production, create new environment instead.

### Enable/Disable Addons

Control which ArgoCD addons are deployed:

```yaml
csoc:
  addon_configs:
    <addon_name>:
      namespace: <namespace>
      create_namespace: true
    <another_addon>:  # Added
      namespace: <namespace>
      create_namespace: true
```

After modifying `addon_configs`, run `terragrunt apply --all` to update IAM roles and ArgoCD ApplicationSets.

## Customizing IAM Policies

IAM policies are organized in `iam/<provider>/` with environment-specific overrides. See [`iam/README.md`](../iam/README.md) for policy organization and resolution logic.

### Override Default Policy

To customize permissions for a specific environment:

1. **Create environment-specific policy directory**:
   ```bash
   # For csoc hub
   mkdir -p iam/<provider>/<csoc_alias>/csoc/<addon_name>

   # For spoke
   mkdir -p iam/<provider>/<csoc_alias>/<spoke_alias>/<addon_name>
   ```

2. **Copy default policy as template**:
   ```bash
   # For csoc hub
   cp iam/<provider>/_default/<addon_name>/inline-policy.json iam/<provider>/<csoc_alias>/csoc/<addon_name>/inline-policy.json

   # For spoke
   cp iam/<provider>/_default/<addon_name>/inline-policy.json iam/<provider>/<csoc_alias>/<spoke_alias>/<addon_name>/inline-policy.json
   ```

3. **Edit policy** with required customizations (scope resources, add conditions, etc.)

4. **Apply changes**:
   ```bash
   cd live/<provider>/<region>/<csoc_alias>
   terragrunt plan --all  # Review IAM role policy changes
   terragrunt apply --all
   ```

Environment-specific policies completely replace defaults (no merging). See [`iam/README.md`](../iam/README.md#resolution-logic) for precedence rules.

### Add New Service IAM Policy

To grant permissions for a new addon:

1. **Create policy file**:
   ```bash
   mkdir -p iam/aws/_default/ack-opensearch
   ```

2. **Define policy** (`iam/aws/_default/ack-opensearch/policy.json`):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "es:CreateDomain",
           "es:DeleteDomain",
           "es:DescribeDomain",
           "es:UpdateDomainConfig"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

3. **Add addon to secrets.yaml**:
   ```yaml
   csoc:
     addon_configs:
       ack-opensearch:
         namespace: ack-system
   ```

4. **Update combination** (if needed):

   The `csoc/aws` combination automatically creates IAM roles for all addons in `addon_configs`, so no code changes are required if using the standard pattern.

5. **Apply**:
   ```bash
   terragrunt apply --all
   ```

See [`iam/README.md`](../iam/README.md) for policy organization details and format examples for AWS, Azure, and GCP.

## Customizing ArgoCD Addons

ArgoCD addon configuration uses three files: `catalog.yaml` (available addons), `enablement.yaml` (which to deploy), and `values.yaml` (Helm configuration). See [`argocd/README.md`](../argocd/README.md#addon-catalog) for catalog structure details.

### Add New Addon

1. **Add to catalog** (`argocd/addons/csoc/catalog.yaml`):
   ```yaml
   addons:
     - name: prometheus
       helmChart: oci://registry-1.docker.io/bitnamicharts/kube-prometheus
       version: 8.3.0
       namespace: monitoring
       wave: 0
   ```

2. **Enable deployment** (`argocd/addons/csoc/enablement.yaml`):
   ```yaml
   enabled:
     - prometheus  # Add to list
   ```

3. **Configure values** (`argocd/addons/csoc/values.yaml`):
   ```yaml
   prometheus:
     prometheus:
       retention: 30d
   ```

4. **Commit and sync**:
   ```bash
   git add argocd/addons/csoc/ && git commit -m "Add Prometheus" && git push
   argocd app sync -l argocd.argoproj.io/instance=csoc-addons
   ```

## Extending Terraform Modules

To add functionality to existing modules or create new modules:

### Modify Existing Module

Example: Add encryption configuration to `aws-vpc` module

1. **Edit module** (`terraform/catalog/modules/aws-vpc/main.tf`):
   ```hcl
   resource "aws_ebs_encryption_by_default" "this" {
     count = var.enable_ebs_encryption ? 1 : 0
     enabled = true
   }
   ```

2. **Add variable** (`terraform/catalog/modules/aws-vpc/variables.tf`):
   ```hcl
   variable "enable_ebs_encryption" {
     type        = bool
     default     = false
     description = "Enable EBS encryption by default"
   }
   ```

3. **Update combination** (`terraform/catalog/combinations/csoc/aws/main.tf`):
   ```hcl
   module "vpc" {
     source = "../../../modules/aws-vpc"
     # ... existing configuration ...
     enable_ebs_encryption = var.enable_ebs_encryption
   }
   ```

4. **Add combination variable** (`terraform/catalog/combinations/csoc/aws/variables.tf`):
   ```hcl
   variable "enable_ebs_encryption" {
     type    = bool
     default = false
   }
   ```

5. **Update unit** (`terraform/units/csoc/terragrunt.hcl`):
   ```hcl
   inputs = {
     # ... existing inputs ...
     enable_ebs_encryption = values.enable_ebs_encryption
   }
   ```

6. **Configure in secrets.yaml**:
   ```yaml
   csoc:
     enable_ebs_encryption: true
   ```

7. **Test and apply**:
   ```bash
   cd live/aws/us-east-1/gen3-kro-dev
   terragrunt plan --all
   terragrunt apply --all
   ```

### Create New Module

Example: Create `aws-opensearch` module

1. **Create module directory**:
   ```bash
   mkdir -p terraform/catalog/modules/aws-opensearch
   ```

2. **Define module files**:

   **main.tf**:
   ```hcl
   resource "aws_opensearch_domain" "this" {
     domain_name    = var.domain_name
     engine_version = var.engine_version

     cluster_config {
       instance_type  = var.instance_type
       instance_count = var.instance_count
     }

     vpc_options {
       subnet_ids = var.subnet_ids
     }
   }
   ```

   **variables.tf**:
   ```hcl
   variable "domain_name" {
     type = string
   }

   variable "engine_version" {
     type    = string
     default = "OpenSearch_2.11"
   }

   variable "instance_type" {
     type    = string
     default = "t3.small.search"
   }

   variable "instance_count" {
     type    = number
     default = 1
   }

   variable "subnet_ids" {
     type = list(string)
   }
   ```

   **outputs.tf**:
   ```hcl
   output "domain_endpoint" {
     value = aws_opensearch_domain.this.endpoint
   }

   output "domain_arn" {
     value = aws_opensearch_domain.this.arn
   }
   ```

   **versions.tf**:
   ```hcl
   terraform {
     required_version = ">= 1.5.0"
     required_providers {
       aws = {
         source  = "hashicorp/aws"
         version = "~> 5.0"
       }
     }
   }
   ```

3. **Integrate into combination** (`terraform/catalog/combinations/csoc/aws/main.tf`):
   ```hcl
   module "opensearch" {
     source = "../../../modules/aws-opensearch"

     domain_name    = "${var.cluster_name}-opensearch"
     instance_type  = "t3.small.search"
     instance_count = 1
     subnet_ids     = module.vpc.private_subnets

     depends_on = [module.vpc]
   }
   ```

4. **Export outputs** (`terraform/catalog/combinations/csoc/aws/outputs.tf`):
   ```hcl
   output "opensearch_endpoint" {
     value = module.opensearch.domain_endpoint
   }
   ```

5. **Create IAM policy** (see "Add New Service IAM Policy" section above)

6. **Document module** following [`terraform/catalog/modules/README.md`](../terraform/catalog/modules/README.md) template

## Extending KRO Graphs

KRO ResourceGraphDefinitions declaratively define infrastructure patterns.

### Create New Graph

Example: PostgreSQL RDS instance graph

1. **Create graph file** (`argocd/graphs/aws/rds-postgres-rgd.yaml`):
   ```yaml
   apiVersion: kro.run/v1alpha1
   kind: ResourceGraphDefinition
   metadata:
     name: rds-postgres
   spec:
     schema:
       apiVersion: v1alpha1
       kind: RDSPostgres
       spec:
         instanceClass: string
         allocatedStorage: integer
         databaseName: string
         masterUsername: string
     resources:
       - id: db-subnet-group
         template:
           apiVersion: rds.services.k8s.aws/v1alpha1
           kind: DBSubnetGroup
           spec:
             name: ${schema.metadata.name}-subnet-group
             subnetIDs:
               - ${schema.spec.subnetIDs[0]}
               - ${schema.spec.subnetIDs[1]}
       - id: db-instance
         template:
           apiVersion: rds.services.k8s.aws/v1alpha1
           kind: DBInstance
           spec:
             dbInstanceIdentifier: ${schema.metadata.name}
             dbInstanceClass: ${schema.spec.instanceClass}
             engine: postgres
             allocatedStorage: ${schema.spec.allocatedStorage}
             masterUsername: ${schema.spec.masterUsername}
             dbSubnetGroupName: ${resources.db-subnet-group.metadata.name}
   ```

2. **Commit and push**:
   ```bash
   git add argocd/graphs/aws/rds-postgres-rgd.yaml
   git commit -m "Add RDS PostgreSQL graph"
   git push
   ```

3. **Sync graphs ApplicationSet**:
   ```bash
   argocd app sync -l argocd.argoproj.io/instance=graphs
   ```

4. **Create graph instance** (in application repository):
   ```yaml
   apiVersion: v1alpha1
   kind: RDSPostgres
   metadata:
     name: metadata-db
   spec:
     instanceClass: db.t3.micro
     allocatedStorage: 20
     databaseName: metadata
     masterUsername: admin
     subnetIDs:
       - subnet-abc123
       - subnet-def456
   ```

## Best Practices

### Secret Management

**Never commit secrets to Git.** Always keep sensitive values in:
- `live/.../secrets.yaml` (gitignored)
- Cloud provider secret managers (AWS Secrets Manager, Azure Key Vault, GCP Secret Manager)
- ExternalSecrets operator syncs secrets from cloud providers to Kubernetes

### Testing Changes

Before applying customizations to production:

1. **Plan first**: Always run `terragrunt plan --all` to preview changes
2. **Test in dev environment**: Apply changes to development environment first
3. **Validate**: Check resource creation, ArgoCD sync status, application health
4. **Document**: Update relevant README files with customization details

### Version Control

- **Commit infrastructure changes**: All Terraform, IAM, and ArgoCD modifications
- **Tag releases**: Use `./scripts/version-bump.sh` for semantic versioning
- **Branch for features**: Create feature branches for significant customizations
- **Review before merge**: Use pull requests for code review

See [`CONTRIBUTING.md`](../../CONTRIBUTING.md) for contribution guidelines.

---
**Last updated:** 2025-10-28
