# ArgoCD GitOps

GitOps deployment manifests for bootstrapping Gen3 platform addons and KRO ResourceGraphDefinitions across hub and spoke clusters using ArgoCD ApplicationSets.

## Architecture

we uses a hierarchical GitOps topology:

1. **Terraform deploys ArgoCD**: The `argocd` Terraform module installs ArgoCD in the hub cluster and creates initial ApplicationSets from `argocd/bootstrap/`
2. **argocd/bootstrap/**: contains:
   - **csoc-addons**: Hub cluster addons (KRO, ACK controllers, ExternalSecrets, any other components - add here)
   - **spoke-addons**: Spoke cluster addons (view only addons for spoke, possibly with resource adoption capabilities)
   - **graphs**: KRO ResourceGraphDefinitions for application declarative infrastructure (VPCs, clusters, databases)
3. **Catalog-driven configuration**: ApplicationSets read addon definitions from `argocd/addons/csoc/catalog.yaml` and values from `argocd/addons/csoc/values.yaml`

## Directory Structure

```
argocd/
├── bootstrap/                   # App-of-apps ApplicationSets (deployed by Terraform)
│   ├── csoc-addons.yaml         # Hub addon ApplicationSet
│   ├── spoke-addons.yaml        # Spoke addon ApplicationSet
│   ├── graphs.yaml              # KRO graph ApplicationSet
│   ├── app-instances.yaml       # App instance deployments
│   └── graph-instances.yaml     # Graph instance deployments
├── addons/
│   └── csoc/                    # Hub addon catalog and configuration
│       ├── catalog.yaml         # Available addons (Helm chart sources, versions)
│       ├── enablement.yaml      # Which addons to deploy
│       └── values.yaml          # Addon-specific Helm values
├── graphs/                      # KRO ResourceGraphDefinitions
│   ├── aws/
│   │   ├── eks-basic-rgd.yaml
│   │   ├── eks-cluster-rgd.yaml
│   │   └── vpc-network-rgd.yaml
│   ├── azure/
│   ├── google/
│   └── instances/               # Graph instance definitions
├── spokes/                      # Spoke-specific overlays
│   └── <spoke_alias>/           # Per-spoke configuration
│       ├── values.yaml          # Spoke-level overrides
│       ├── addons/              # Spoke-specific addon configurations
│       ├── cluster-values/      # Kubernetes cluster values
│       └── infrastructure/      # Infrastructure definitions
└── charts/                      # Helm chart templates
    └── addons-appset/           # ApplicationSet Helm chart
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
```

## Bootstrap Flow

### 1. Terraform Invocation

The `argocd` Terraform module (called by `terraform/catalog/combinations/csoc/<provider>/main.tf`) performs:

1. **Install ArgoCD Helm chart**: Deploys ArgoCD server, repo-server, application-controller to `argocd` namespace
2. **Create cluster secret**: Registers hub cluster with ArgoCD (enables self-management)
3. **Deploys bootstrap ApplicationSets**: uses the templated manifest in `terraform/catalog/combinations/csoc/bootstrap` to deploy components from `argocd/bootstrap/*.yaml` to ArgoCD namespace

**Key Terraform outputs:**
- `argocd_server_endpoint`: ArgoCD UI URL (retrieved from Kubernetes service)
- `argocd_admin_password`: Initial admin password (retrieved from Kubernetes secret)

### 2. ApplicationSet Sync

ArgoCD ApplicationSet controller evaluates generators and creates individual `Application` resources:

**csoc-addons ApplicationSet** (`bootstrap/csoc-addons.yaml`):
- **Generators**: Matrix of hub clusters (`fleet_member=control-plane`) × addon catalog (`addons/csoc/catalog.yaml`)
- **Filters**: Only deploys addons listed in `addons/csoc/enablement.yaml`
- **Sources**: Helm chart (from catalog) + values repository (from `addons/csoc/values.yaml`)
- **Sync waves**: KRO deployed in wave `-1` (must be ready before ResourceGraphDefinitions), all others in wave `0`

**app-instances ApplicationSet** (`bootstrap/app-instances.yaml`):
- **Generators**: Git files matching `spokes/<spoke_alias>/*/values.yaml`
- **Purpose**: Deploy application instances to spoke clusters based on spoke-specific configurations

**graphs ApplicationSet** (`bootstrap/graphs.yaml`):
- **Generators**: Git files matching `graphs/<provider>/*.yaml`
- **Purpose**: Deploy KRO ResourceGraphDefinitions for declarative infrastructure provisioning

**graph-instances ApplicationSet** (`bootstrap/graph-instances.yaml`):
- **Generators**: Git files matching `graphs/instances/*.yaml`
- **Purpose**: Deploy instantiated KRO ResourceGraph instances

**spoke-addons ApplicationSet** (`bootstrap/spoke-addons.yaml`):
- **Generators**: Matrix of spoke clusters (`fleet_member=spoke`) × spoke addon catalogs at `spokes/<spoke_alias>/addons/`
- **Purpose**: Deploy subset of hub capabilities to spoke environments for specific use cases

### 3. Addon Deployment

Each addon Application syncs its Helm chart with values from the repository. Example addon flow:

1. ArgoCD pulls `<addon_name>` Helm chart from the specified source URL (can be an OCI registry or Git repository)
2. Merges values from `addons/csoc/values.yaml` (e.g., IAM role ARN, resource limits)
3. Deploys to target namespace
4. Annotates ServiceAccount with IAM role for Pod Identity

## Addon Catalog

`addons/csoc/catalog.yaml` defines available addons as a YAML array:

```yaml
- addon: kro
  repoURL: oci://ghcr.io/kro-run/kro/kro
  revision: 0.4.1
  chart: kro
  sync_wave: "-1"

- addon: ack-s3
  repoURL: oci://public.ecr.aws/aws-controllers-k8s/s3-chart
  revision: 1.0.18
  chart: s3-chart
  sync_wave: "0"
```

`addons/csoc/enablement.yaml` controls which addons are active:

```yaml
enablement:
  # KRO - Required first for ResourceGraphDefinitions
  <addon-name>:
    enabled: true

  # ACK Controllers - All enabled for hub
  <controller-name>:
    enabled: true
```

Note: The values.yaml file provides templated addon-specific configuration (currently in development).

## Secrets Strategy

ArgoCD Application manifests **do not** directly contain sensitive provider information. These are passed via Kubernetes Secrets.

1. **ExternalSecrets Operator**: Syncs secrets from cloud provider secret managers (AWS Secrets Manager, Azure Key Vault, GCP Secret Manager) to Kubernetes Secrets
2. **Helm value references**: Addons are configured to reference existing Secret resources (created by ExternalSecrets)

## Sync Operations

ApplicationSets enable automatic synchronization:

```yaml
spec:
  template:
    spec:
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

## Health Checks

ArgoCD monitors resource health using built-in and custom health checks. Common statuses:

- **Healthy**: Resource is running and ready
- **Progressing**: Resource is being created/updated
- **Degraded**: Resource has warnings or non-fatal errors
- **Suspended**: Resource is intentionally paused

View application health:
```bash
argocd app get <csoc-addon-name>
argocd app list --selector argocd.argoproj.io/instance=<instance-name>
```

## Troubleshooting

**ApplicationSet not creating Applications:**
- Check generator output: `kubectl describe applicationset <applicationset-name> -n argocd`
- Verify cluster labels: `kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster -o yaml`

**Application stuck in Progressing:**
- View sync status: `argocd app get <app-name>`
- Check resource events: `kubectl describe <resource> -n <namespace>`

**Addon deployment failures:**
- View Helm release status: `helm list -n <namespace>`
- Check pod logs: `kubectl logs -n <namespace> <pod-name>`

**Secrets not syncing:**
- Verify ExternalSecrets operator is healthy: `kubectl get pods -n external-secrets`
- Check SecretStore configuration: `kubectl get secretstore -n <namespace>`

See [`docs/guides/operations.md`](../docs/guides/operations.md) for detailed troubleshooting workflows.

---
**Last updated:** 2025-10-28
