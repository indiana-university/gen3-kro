# Addons ApplicationSet - Usage Guide

## Summary of Changes

The `addons.yaml` ApplicationSet has been updated to:

1. **Generate applications for each cluster** (both hub and spoke)
2. **Use the centralized addon catalog** from `bootstrap/addons/catalog.yaml`
3. **Reference location-specific values**:
   - Hub clusters: `bootstrap/addons/values.yaml`
   - Spoke clusters: `spokes/{tenant}/addons/values.yaml`
4. **Support enablement control** via `enablement.yaml` files (per location)

## How It Works

### Generator Strategy

The ApplicationSet uses a **matrix generator** that creates the Cartesian product of:
- All registered clusters (via `clusters: {}` generator)
- All addons in the catalog (via `git` file generator)

This means: **One Application per addon per cluster**

Example Applications created:
- `hub-staging-kro`
- `hub-staging-ack-ec2`
- `spoke1-kro`
- `spoke1-ack-ec2`

### Cluster Routing

The ApplicationSet determines which values to use based on cluster labels:

```yaml
# Hub cluster (has fleet_member: control-plane)
valueFiles:
  - $values/bootstrap/addons/values.yaml

# Spoke cluster (tenant: spoke1)
valueFiles:
  - $values/spokes/spoke1/addons/values.yaml
```

### Filtering by Enablement

While all Applications are created, you can control which are **actually deployed** using the enablement files:

**For manual enablement filtering**, modify the enablement.yaml:
```yaml
# bootstrap/addons/enablement.yaml (hub)
enablement:
  kro:
    enabled: true    # Deploy kro to hub
  ack-ec2:
    enabled: true    # Deploy ack-ec2 to hub
  ack-rds:
    enabled: false   # Don't deploy ack-rds to hub
```

```yaml
# spokes/spoke1/addons/enablement.yaml
enablement:
  kro:
    enabled: true    # Deploy kro to spoke1
  ack-ec2:
    enabled: true    # Deploy ack-ec2 to spoke1
  ack-rds:
    enabled: true    # Deploy ack-rds to spoke1 (different from hub!)
```

**Note**: The current implementation creates all Applications. To prevent deployment of disabled addons, you would need to:
1. Add a selector in the generator based on enablement status, OR
2. Use ArgoCD App-of-Apps pattern with conditional inclusion, OR
3. Simply delete/ignore the Applications you don't want (they won't sync)

## Required Cluster Configuration

Each cluster registered with ArgoCD must have these annotations and labels:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    fleet_member: "control-plane"  # Only for hub, omit for spokes
    tenant: "spoke1"                # For spoke clusters (identifies which spoke)
  annotations:
    addons_repo_url: "https://github.com/your-org/gen3-kro.git"
    addons_repo_revision: "main"
    addons_repo_basepath: "argocd"
    aws_region: "us-east-1"
    # Add IRSA role ARNs for ACK controllers
    ack-ec2_irsa_role_arn: "arn:aws:iam::123456789012:role/ack-ec2-controller"
    ack-eks_irsa_role_arn: "arn:aws:iam::123456789012:role/ack-eks-controller"
    # ... more as needed
```

## Sync Waves

The ApplicationSet uses sync waves to ensure proper ordering:

- **Wave -1**: KRO
  - Must be installed first because other components may use ResourceGraphDefinitions
- **Wave 0**: All other addons
  - ACK controllers, platform components, etc.

## Values Merging

Helm values are merged in this order (later overrides earlier):

1. **Default chart values** (from the Helm chart itself)
2. **Values file** (from `bootstrap/addons/values.yaml` or `spokes/{tenant}/addons/values.yaml`)
3. **Inline values** (in the ApplicationSet template)

The inline values section handles:
- KRO version tag
- ACK controller IRSA role ARNs
- AWS region configuration

## Examples

### Example 1: Hub Cluster Deployment

For a hub cluster named `gen3-kro-hub-staging`:

```bash
# Applications created:
kubectl get applications -n argocd | grep gen3-kro-hub-staging

gen3-kro-hub-staging-kro                   # Deploys KRO
gen3-kro-hub-staging-ack-ec2              # Deploys ACK EC2 controller
gen3-kro-hub-staging-ack-eks              # Deploys ACK EKS controller
# ... and so on for each addon in catalog
```

Values loaded from:
- `bootstrap/addons/values.yaml`

### Example 2: Spoke Cluster Deployment

For a spoke cluster named `spoke1-cluster` with label `tenant: spoke1`:

```bash
# Applications created:
kubectl get applications -n argocd | grep spoke1-cluster

spoke1-cluster-kro                        # Deploys KRO
spoke1-cluster-ack-ec2                   # Deploys ACK EC2 controller
# ... and so on
```

Values loaded from:
- `spokes/spoke1/addons/values.yaml`

### Example 3: Adding a New Addon

1. Add to catalog:
```yaml
# bootstrap/addons/catalog.yaml
items:
  # ... existing addons ...
  - addon: cert-manager
    repoURL: https://charts.jetstack.io
    revision: v1.13.0
    chartPath: cert-manager
```

2. Enable in hub:
```yaml
# bootstrap/addons/enablement.yaml
enablement:
  cert-manager:
    enabled: true
```

3. Configure values:
```yaml
# bootstrap/addons/values.yaml
cert-manager:
  installCRDs: true
  global:
    leaderElection:
      namespace: cert-manager
```

4. The ApplicationSet will automatically create `{cluster-name}-cert-manager` Applications

## Troubleshooting

### Application not appearing

Check:
1. Is the addon in `catalog.yaml`?
2. Is the cluster registered with ArgoCD?
3. Does the cluster have required annotations?

```bash
kubectl get secret -n argocd <cluster-name> -o yaml
```

### Application stuck in Progressing

Check:
1. Application events: `kubectl describe application -n argocd <app-name>`
2. Does the values file exist in the expected location?
3. Are there syntax errors in the values file?

### Wrong values being applied

Check:
1. Cluster labels (`fleet_member`, `tenant`)
2. Values file path in Application spec
3. Values file content

```bash
kubectl get application -n argocd <app-name> -o yaml | grep -A 10 valueFiles
```

## Integration with Terraform

The cluster annotations should be set during cluster registration, typically in Terraform:

```hcl
# terraform/modules/eks-hub/argocd-cluster-secret.tf
resource "kubernetes_secret" "argocd_cluster" {
  metadata {
    name      = var.cluster_name
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "fleet_member"                   = "control-plane"
    }
    annotations = {
      "addons_repo_url"      = var.gitops_repo_url
      "addons_repo_revision" = var.gitops_repo_revision
      "addons_repo_basepath" = "argocd"
      "aws_region"           = var.aws_region
      # ACK IRSA role ARNs
      "ack-ec2_irsa_role_arn" = module.ack_ec2_irsa.role_arn
      # ... more
    }
  }
  # ... cluster connection details
}
```

## Next Steps

To fully implement enablement-based filtering (so disabled addons don't create Applications at all):

1. **Option A**: Use progressive rollout strategy
   - Keep current implementation
   - Manually delete unwanted Applications
   - Use enablement.yaml as documentation of intent

2. **Option B**: Add enablement to catalog
   - Merge enablement data into catalog items during generation
   - Filter at generator level using selector expressions

3. **Option C**: Split into multiple ApplicationSets
   - One ApplicationSet per addon category
   - Use cluster selectors to target specific clusters
   - More granular but more files to maintain
