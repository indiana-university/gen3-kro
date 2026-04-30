---
description: 'ArgoCD ApplicationSets, Helm charts, addon configuration, and sync-wave ordering for gen3-kro'
applyTo: "argocd/**"
---

# ArgoCD & Component Stack

## Sync-Wave Ordering

| Wave | Component | Notes |
|------|-----------|-------|
| -30 | KRO controller | Registers CRDs before any RGDs |
| -20 | Bootstrap ApplicationSet | Entry-point; creates per-addon ApplicationSets |
| 1 | ACK controllers | Talk to real AWS APIs; one controller per service |
| 10 | ResourceGraphDefinitions | Applied after all controllers are ready |
| 15 | KRO instances (cluster-level) | ClusterResources, DNS, ACM |
| 30 | KRO instances (infrastructure) | Foundation, Database, Compute, Search, IAM, etc. |

ArgoCD is bootstrapped by Helm directly — it is not a sync-wave item.

## Bootstrap Models

### EKS CSOC

1. `scripts/install.sh apply` → Terraform creates EKS + ArgoCD + bootstrap ApplicationSet
2. Bootstrap ApplicationSet reads `argocd/bootstrap/` → creates per-addon ApplicationSets
3. ApplicationSets render addons from `argocd/addons/addons.yaml` filtered by `cluster_type: eks`

Adding a new EKS component:
- Add entry to `argocd/addons/addons.yaml` with correct sync-wave and `cluster_type: eks`
- Update ACK controller table in `.github/copilot-instructions.md` if applicable

### Local CSOC

1. `scripts/kind-local-test.sh install` → Helm installs ArgoCD on Kind cluster
2. Script creates ArgoCD cluster Secret with `fleet_member: control-plane` and `aws_account_id`
3. Script applies bootstrap ApplicationSets (`local-addons`, `local-infra-instances`)
4. ArgoCD reconciles: application-sets chart → per-addon ApplicationSets → Applications

Adding a new local component:
- Add entry to `argocd/addons/addons.yaml` with `cluster_type: kind`
- Follow Kind ACK entry pattern: no IRSA, `ignoreDifferences` on Deployment env
- Test instances → `argocd/local-kind/test/tests/`
- Production infra instances → `argocd/local-kind/test/infrastructure/`

## Fleet Directory Structure

```
argocd/
├── fleet/spoke1/
│   ├── infrastructure/
│   │   ├── instances.yaml           # Infra-tier KRO CR instances
│   │   └── infrastructure-values.yaml
│   ├── cluster-level-resources/
│   │   ├── app.yaml                 # AwsGen3ClusterResources1 instance
│   │   └── cluster-values.yaml      # $values ref for cluster-level-resources chart
│   └── {hostname}/
│       ├── app.yaml                 # AwsGen3Helm1/2 instance
│       └── values.yaml              # $values ref for gen3-helm chart
└── local-kind/test/
    ├── infrastructure/              # Real-AWS infra instances
    ├── tests/                       # KRO capability test instances
    └── cluster-resources/
```

The `fleet-instances` ApplicationSet picks up every `*.yaml` in `argocd/fleet/{spoke}/`,
excluding `values.yaml` and `cluster-values.yaml` (those are $values refs for
multi-source Applications). All KRO instances are ArgoCD-managed — never kubectl apply.

## Helm Chart Conventions

RGD templates: `argocd/charts/resource-groups/templates/<name>-rg.yaml`

KRO handles parameterization via RGD schema spec, not Helm values. The `Chart.yaml`
and `values.yaml` exist for structural parity between EKS and local.

## ACK Controller Configuration

**EKS CSOC:** ACK uses IRSA — no credentials stored in the cluster.

**Local CSOC:** ACK uses K8s Secret `ack-aws-credentials` in namespace `ack`,
created from `~/.aws/credentials`. Renew with:
```bash
bash scripts/kind-local-test.sh inject-creds
```

## Adding ACK Controllers (Local CSOC)

1. Add entry to `argocd/addons/addons.yaml`:
   - Key suffix: `-kind` (e.g., `ack-newservice-kind`)
   - `selector: cluster_type: kind`
   - No IRSA serviceAccount annotations
   - `ignoreDifferences` on Deployment env
2. `chartRepository: "public.ecr.aws/aws-controllers-k8s"` (no `oci://` prefix)
3. `aws.region: '{{.metadata.annotations.aws_region}}'`
4. Update the ACK controllers table in `.github/copilot-instructions.md`

## ArgoCD Auto-Sync Behaviour

| App type | Auto-Sync | Prune | Self-Heal |
|----------|-----------|-------|-----------|
| RGD apps (`kro-local-rgs-*`) | Yes | Yes | Yes |
| Instance apps (`*-infra-instance`) | Yes | Yes | No |

`git push` → ArgoCD detects change (~3 min) → syncs → KRO reconciles → AWS resources updated.
