# ArgoCD GitOps

This tree is the GitOps source for the CSOC control plane. Terraform creates the first `bootstrap` ApplicationSet; ArgoCD then reconciles the manifests in `argocd/bootstrap/`.

## Layout

```text
argocd/
├── bootstrap/
│   ├── csoc-controllers.yaml   # controller AppSets from csoc/controllers values
│   ├── csoc-kro.yaml           # recursive Application for csoc/kro
│   ├── multi-account.yaml      # per-spoke namespaces/CARM/secret-writer SAs
│   └── fleet-instances.yaml    # per-spoke KRO instances
├── csoc/
│   ├── controllers/            # base + cluster-type controller values
│   ├── helm/                   # csoc-controllers, multi-account, kro-aws-instances
│   └── kro/                    # Gen3 and test ResourceGraphDefinitions
└── spokes/
    └── <spoke>/                # per-spoke infrastructure and workload values
```

## Reconciliation

```text
Terraform
└── bootstrap ApplicationSet
    └── bootstrap Application (argocd/bootstrap)
        ├── csoc-controllers ApplicationSet -> controller Applications
        ├── csoc-kro ApplicationSet -> csoc-kro Application
        ├── multi-account ApplicationSet -> per-spoke account resources
        └── fleet-instances ApplicationSet -> <spoke>-fleet-instances Applications
```

## Waves

| Wave | Resource | Purpose |
|------|----------|---------|
| -30 | `self-managed-kro` | KRO controller |
| -20 | `csoc-controllers` | Generates controller ApplicationSets |
| 1 | `ack-*` | ACK controllers |
| 5 | `multi-account` | Per-spoke namespaces, ACK CARM wiring, and secret-writer SAs |
| 10 | `csoc-kro` | Recursive Gen3 RGD delivery from `csoc/kro` |
| 15 | `external-secrets` | External Secrets Operator |
| 30 | `fleet-instances` | Per-spoke KRO instance chart |

## Naming

The `csoc-controllers` chart creates one ApplicationSet per enabled controller key. Generated ArgoCD Applications now use the ApplicationSet key as the app name, for example `ack-rds`, not `ack-rds-<cluster>`. Set `appendClusterName: true` on a controller value only when a single ApplicationSet must target multiple clusters and needs unique app names.

## Values

Controller ApplicationSets merge values in this order:

1. `argocd/csoc/controllers/values.yaml`
2. `argocd/csoc/controllers/<cluster_type>-overrides/addons.yaml`
3. optional `argocd/spokes/<spoke>/addons/<chart>/values.yaml`

Fleet instances use `argocd/csoc/helm/kro-aws-instances` plus `argocd/spokes/{{.name}}/infrastucture-values.yaml`, where `{{.name}}` is the ArgoCD cluster generator name.

## Cluster Secret Contract

ApplicationSets use the ArgoCD cluster generator. Terraform writes the CSOC cluster secret labels and annotations.

| Key | Used by |
|-----|---------|
| `fleet_member=control-plane` | CSOC bootstrap AppSets |
| `cluster_type=eks|kind` | controller override selection |
| `ack_management_mode=self_managed` | ACK controller selectors |
| `enable_kro_csoc_rgs=true` | `csoc-kro` |
| `enable_external_secrets=true` | External Secrets |
| `enable_multi_acct=true` | `multi-account` |
| `csoc_assume_role_arn` | Secret-writer service account IRSA role |
| `enable_infra_instances=true` | `fleet-instances` |
| `addons_repo_*` | controller and RGD sources |
| `fleet_repo_*` | spoke instance sources |

## Validation

```bash
helm template csoc-controllers argocd/csoc/helm/csoc-controllers \
  -f argocd/csoc/controllers/values.yaml \
  -f argocd/csoc/controllers/eks-overrides/addons.yaml

helm template kro-aws-instances argocd/csoc/helm/kro-aws-instances \
  -f argocd/spokes/spoke1/infrastucture-values.yaml
```
