# ArgoCD GitOps

GitOps manifests that install controllers/CRDs and sync KRO ResourceGraphDefinitions (RGDs) and addon charts across hub and spoke clusters.

## Architecture

1. Terraform installs ArgoCD and applies `argocd/bootstrap/*.yaml`.
2. Bootstrap ApplicationSets:
   - `csoc-controller-appset.yaml`: ACK/KRO/external-secrets controllers for hub clusters.
   - `csoc-crds-appset.yaml`: ACK/KRO/ESO CRDs.
   - `csoc-rgds-per-cloud.yaml`: Provider RGDs from `argocd/csoc-addons/rgds/<provider>/`.
   - `csoc-rgds-graph-of-graphs.yaml`: Multi-controller RGDs from `argocd/csoc-addons/rgds/graph-of-graphs/`.
3. Kustomize overlays and ApplicationSets use cluster labels (`fleet_member=control-plane` or `spoke`) plus repo annotations to target the right cluster.

## Directory Structure

```
argocd/
├── bootstrap/                        # ApplicationSets applied by Terraform
│   ├── csoc-controller-appset.yaml   # Controllers (ACK, KRO, ESO, metrics)
│   ├── csoc-crds-appset.yaml         # CRDs for controllers
│   ├── csoc-rgds-per-cloud.yaml      # Per-cloud RGDs (aws/azure/gcp)
│   └── csoc-rgds-graph-of-graphs.yaml# Composite graphs
├── csoc-addons/
│   ├── controllers/                  # Controller Helm releases
│   ├── crds/                         # CRDs for controllers
│   └── rgds/                         # KRO RGDs (per cloud + composites)
├── deployments/                      # Spoke overlays and infrastructure apps
└── .instance-library-(for-reference)/# Sample instance manifests by provider
```

## Bootstrap Flow

1) Terraform installs ArgoCD and seeds bootstrap manifests.  
2) Controller/CRD ApplicationSets sync first (negative sync waves).  
3) RGD ApplicationSets sync next; ArgoCD handles namespace creation and SSA.  
4) Downstream Applications/overlays consume RGDs via status fields.

Key outputs from Terraform: `argocd_server_endpoint`, `argocd_admin_password`.

## Usage

- Check ApplicationSet health:
```bash
kubectl get applicationset -n argocd
```
- Check controller or RGD apps:
```bash
argocd app list -l app.kubernetes.io/name=controllers
argocd app list -l app.kubernetes.io/name=rgds
```
- Manual RGD apply (fallback):
```bash
kubectl apply -k argocd/csoc-addons/rgds/aws
```

## Troubleshooting

- ApplicationSet stuck: `kubectl describe applicationset <name> -n argocd`
- Controller pod issues: `kubectl logs -n ack-system -l app.kubernetes.io/name=ack-ec2-controller`
- RGD missing: `kubectl get rgd -n kro-system`; resync `csoc-rgds-per-cloud`.
- Secrets: ensure ExternalSecrets controller is healthy and SecretStores are configured.

See `docs/guides/operations.md` for operational workflows.
