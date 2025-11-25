# Customization Guide

How to adjust Gen3-KRO infrastructure: environment config, IAM, addons, modules, and KRO graphs.

## Overview

Customization layers:
1. **Environment**: `live/<provider>/<region>/<csoc_alias>/secrets.yaml`
2. **IAM**: `iam/<provider>/<csoc_alias>/.../inline-policy.json`
3. **Modules/Combinations**: `terraform/catalog/modules/` and `/combinations/`
4. **ArgoCD addons**: `argocd/addons/`
5. **KRO graphs**: `argocd/graphs/`

## Customizing Infrastructure via secrets.yaml

Common tweaks go in `secrets.yaml`. Examples:
- Cluster size:
  ```yaml
  csoc:
    k8s_cluster:
      cluster_compute_config:
        default:
          instance_types: ["t3.large"]
          desired_size: 4
          min_size: 2
          max_size: 8
  ```
- VPC layout (recreates VPC if CIDR changes):
  ```yaml
  csoc:
    vpc:
      vpc_cidr: 10.100.0.0/16
      availability_zones: [us-east-1a, us-east-1b, us-east-1c]
      private_subnet_cidrs: [10.100.1.0/24, 10.100.2.0/24, 10.100.3.0/24]
      public_subnet_cidrs: [10.100.101.0/24, 10.100.102.0/24, 10.100.103.0/24]
  ```
- Addons:
  ```yaml
  csoc:
    addon_configs:
      <addon_name>:
        namespace: <namespace>
        create_namespace: true
  ```
Apply with `terragrunt plan --all` then `terragrunt apply --all`.

## Customizing IAM Policies

IAM policies are organized in `iam/<provider>/` with environment-specific overrides. See [`iam/README.md`](../iam/README.md) for policy organization and resolution logic.

Override IAM per environment:
```bash
mkdir -p iam/<provider>/<csoc_alias>/csoc/<addon_name>
cp iam/<provider>/_default/<addon_name>/inline-policy.json iam/<provider>/<csoc_alias>/csoc/<addon_name>/
# edit inline-policy.json
```
For spokes use `iam/<provider>/<csoc_alias>/<spoke_alias>/<addon_name>/`. Overrides replace defaults; see `iam/README.md#resolution-logic`. Apply with `terragrunt plan/apply`.

### Add New Service IAM Policy

Add a new addon policy:
```bash
mkdir -p iam/aws/_default/ack-opensearch
cat > iam/aws/_default/ack-opensearch/policy.json <<'EOF'
{ "Version": "2012-10-17", "Statement": [ { "Effect": "Allow", "Action": ["es:CreateDomain","es:DeleteDomain","es:DescribeDomain","es:UpdateDomainConfig"], "Resource": "*" } ] }
EOF
```
Enable in `secrets.yaml` under `addon_configs` and apply. No combination changes needed with the standard csoc/aws pattern.

## Customizing ArgoCD Addons

Addons use `catalog.yaml` (available), `enablement.yaml` (enabled), and `values.yaml` (Helm values). To add Prometheus:
```yaml
# argocd/addons/csoc/catalog.yaml
addons:
  - name: prometheus
    helmChart: oci://registry-1.docker.io/bitnamicharts/kube-prometheus
    version: 8.3.0
    namespace: monitoring
    wave: 0
# argocd/addons/csoc/enablement.yaml
enabled:
  - prometheus
# argocd/addons/csoc/values.yaml
prometheus:
  prometheus:
    retention: 30d
```
Commit and `argocd app sync -l argocd.argoproj.io/instance=csoc-addons`.

## Extending Terraform Modules

For module changes, keep a thin path: update the module, wire it into combinations, expose variables/outputs, feed inputs via Terragrunt, and toggle via `secrets.yaml`. Example additions:

- Encrypt EBS in `aws-vpc`:
  ```hcl
  # terraform/catalog/modules/aws-vpc/main.tf
  resource "aws_ebs_encryption_by_default" "this" {
    count   = var.enable_ebs_encryption ? 1 : 0
    enabled = true
  }
  # variables.tf
  variable "enable_ebs_encryption" { type = bool, default = false }
  ```
  Pass through combination/unit inputs and set `csoc.enable_ebs_encryption: true` in `secrets.yaml`.

- New module skeleton (`terraform/catalog/modules/aws-opensearch`):
  ```hcl
  # main.tf
  resource "aws_opensearch_domain" "this" {
    domain_name    = var.domain_name
    engine_version = var.engine_version
    cluster_config { instance_type = var.instance_type, instance_count = var.instance_count }
    vpc_options    { subnet_ids = var.subnet_ids }
  }
  # variables.tf
  variable "domain_name" {}
  variable "engine_version" { default = "OpenSearch_2.11" }
  variable "instance_type"  { default = "t3.small.search" }
  variable "instance_count" { default = 1 }
  variable "subnet_ids"     { type = list(string) }
  # outputs.tf
  output "domain_endpoint" { value = aws_opensearch_domain.this.endpoint }
  output "domain_arn"      { value = aws_opensearch_domain.this.arn }
  # versions.tf pins providers as usual
  ```
  Wire into `terraform/catalog/combinations/csoc/aws/main.tf`, export outputs, and expose inputs via Terragrunt.

## Extending KRO Graphs

KRO graphs define deployable patterns. Example RDS PostgreSQL graph (`argocd/graphs/aws/rds-postgres-rgd.yaml`):
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
Commit, sync `argocd app sync -l argocd.argoproj.io/instance=graphs`, then create instances in the application repo.

## Best Practices

### Secret Management

Keep secrets in `live/.../secrets.yaml` (gitignored) or cloud secret managers; ExternalSecrets syncs them to Kubernetes.

### Testing Changes

Before production: `terragrunt plan --all`, test in dev, validate (resources + ArgoCD health), and document.

### Version Control

Commit infra changes, tag releases with `./scripts/version-bump.sh`, use feature branches, and open PRs (`CONTRIBUTING.md`).
