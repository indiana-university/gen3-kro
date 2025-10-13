# Addons Management

This directory contains the configuration files for managing cluster addons across hub and spoke clusters.

## Overview

The addon system is designed to:
1. Deploy KRO, ACK controllers, and platform components
2. Support different configurations for hub vs spoke clusters
3. Enable/disable addons per cluster location
4. Centralize addon definitions while allowing per-cluster customization

## File Structure

```
bootstrap/addons/
├── README.md           # This file
├── catalog.yaml        # Centralized addon registry (all available addons)
├── enablement.yaml     # Which addons are enabled for hub clusters
└── values.yaml         # Configuration values for hub cluster addons

spokes/{tenant}/addons/
├── enablement.yaml     # Which addons are enabled for this spoke
└── values.yaml         # Configuration values for this spoke's addons
```

## Files Explained

### catalog.yaml
Defines all available addons with their Helm chart sources:
```yaml
items:
  - addon: kro
    repoURL: oci://ghcr.io/awslabs/kro/kro-chart
    revision: v0.1.0
    chartPath: ""
  - addon: ack-ec2
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/ec2-chart
    revision: v1.2.24
    chartPath: ""
```

### enablement.yaml
Controls which addons are deployed:
```yaml
enablement:
  kro:
    enabled: true
  ack-ec2:
    enabled: true
  ack-eks:
    enabled: false  # Not deployed to this cluster
```

### values.yaml
Provides addon-specific Helm values:
```yaml
ec2:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: "{{.Values.global.roleArns.ec2}}"
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
```

## How It Works

The `../addons.yaml` ApplicationSet:

1. **Discovers all clusters** registered with ArgoCD
2. **Loads the addon catalog** from `bootstrap/addons/catalog.yaml`
3. **Creates an Application for each addon on each cluster**
4. **References values** from the correct location:
   - Hub clusters (`fleet_member: control-plane`): `bootstrap/addons/values.yaml`
   - Spoke clusters: `spokes/{tenant}/addons/values.yaml`

### Cluster Annotations Required

Each cluster must have these annotations for the ApplicationSet to work:
```yaml
metadata:
  annotations:
    addons_repo_url: "https://github.com/your-org/your-repo.git"
    addons_repo_revision: "main"
    addons_repo_basepath: "argocd"
  labels:
    fleet_member: "control-plane"  # or omit for spoke
    tenant: "spoke1"                # for spoke clusters
```

## Adding a New Addon

1. **Add to catalog.yaml**:
   ```yaml
   - addon: my-new-addon
     repoURL: oci://registry/chart
     revision: v1.0.0
     chartPath: my-chart-name
   ```

2. **Enable in enablement.yaml** (for hub or specific spoke):
   ```yaml
   enablement:
     my-new-addon:
       enabled: true
   ```

3. **Configure in values.yaml** (if needed):
   ```yaml
   my-new-addon:
     specificConfig:
       value: "something"
   ```

## Namespace Mapping

Addons are deployed to namespaces based on naming conventions:
- `kro` → `kro-system`
- `ack-*` → `ack-system`
- Other addons → `{addon-name}-system`

## Sync Waves

- **Wave -1**: KRO (must be installed first for ResourceGraphDefinitions)
- **Wave 0**: All other addons

This ensures KRO is ready before ACK controllers or other components that may use RGDs.

## Troubleshooting

### Addon not deploying
1. Check `enablement.yaml` - is the addon enabled?
2. Verify cluster annotations are set correctly
3. Check ArgoCD Application status: `kubectl get applications -n argocd | grep {cluster-name}-{addon}`

### Values not being applied
1. Ensure `values.yaml` exists in the correct location
2. Check the Application spec for the correct `valueFiles` path
3. Verify the values file syntax is valid YAML

### Wrong namespace
The namespace is automatically determined. To override:
- Modify the `destination.namespace` template in `../addons.yaml`

## Example: Deploying to a New Spoke

1. Create spoke addon directory:
   ```bash
   mkdir -p spokes/spoke2/addons
   ```

2. Copy and customize enablement:
   ```bash
   cp bootstrap/addons/enablement.yaml spokes/spoke2/addons/
   # Edit to enable/disable addons for this spoke
   ```

3. Copy and customize values:
   ```bash
   cp bootstrap/addons/values.yaml spokes/spoke2/addons/
   # Edit to configure spoke-specific values
   ```

4. Register the spoke cluster with ArgoCD with proper labels:
   ```yaml
   metadata:
     labels:
       tenant: spoke2
   ```

The ApplicationSet will automatically detect the new cluster and deploy enabled addons.
