---
applyTo: "argocd/**"
---

# ArgoCD & Component Stack Instructions

These rules apply when editing ArgoCD configuration, Helm charts,
or adding new components to the stack.

## Sync-Wave Ordering

Components must be installed in dependency order:

| Wave | Component | Why this order |
|------|-----------|---------------|
| -30 | KRO controller | Must register CRDs before any RGDs |
| 1 | ACK controllers | Need KRO running, talk to real AWS |
| 5 | ArgoCD | Follows ACK for uniform ordering |
| 10 | ResourceGraphDefinitions | Applied last, after all controllers ready |
| 30 | KRO instances | Infrastructure CRs (instances of RGDs) |

## Bootstrap Models

### EKS CSOC (primary)

gen3-kro uses a **3-layer ApplicationSet** bootstrap:
1. `scripts/install.sh apply` → Terraform creates EKS + ArgoCD + bootstrap ApplicationSet
2. Bootstrap ApplicationSet reads `argocd/bootstrap/` → creates region-level ApplicationSets
3. Region ApplicationSets render addons from `argocd/addons/csoc/addons.yaml`

When adding a new component to the EKS stack:
1. Add its entry to `argocd/addons/csoc/addons.yaml` with the correct sync-wave
2. Follow the Helm values pattern used by existing entries
3. Update the ACK controller table in `.github/copilot-instructions.md` if applicable

### Local CSOC (host-based)

The local cluster mirrors the EKS structure but uses a simplified bootstrap:
1. `scripts/kind-local-test.sh install` → Helm installs ArgoCD directly on the host
2. Script creates ArgoCD cluster Secret (`fleet_member: control-plane`) and injects AWS account ID
3. Script applies bootstrap ApplicationSets (`local-addons`, `local-infra-instances`)
4. ArgoCD reconciles: application-sets chart → per-addon ApplicationSets → Applications

When adding a new component to the local stack:
1. Add its install step to `kind-local-test.sh` → `stage_install()`
2. Document it in `argocd/addons/local/addons.yaml`
3. Follow the sync-wave ordering above

## Helm Chart Conventions

RGD templates live under:
```
argocd/charts/resource-groups/templates/<name>-rg.yaml
```

The `Chart.yaml` and `values.yaml` are kept for structural parity between EKS and local.
KRO handles parameterization via the RGD schema spec, not Helm values.

## ACK Controller Configuration

**EKS CSOC:** ACK controllers use IRSA (IAM Roles for Service Accounts).
No credentials stored in the cluster.

**Local CSOC:** ACK controllers use a K8s Secret (`ack-aws-credentials`) created
from `~/.aws/credentials` on the host. Run `kind-local-test.sh inject-creds` after
renewing credentials.

Both modes: no `endpoint_url` override — controllers talk directly to real AWS APIs.

## Adding New ACK Controllers (Local CSOC)

1. Add the Helm install step to `stage_install()` in `kind-local-test.sh`
2. Use the same pattern: `oci://public.ecr.aws/aws-controllers-k8s/<svc>-chart`
3. Set `aws.region` (no endpoint_url)
4. Update the ACK controller table in `.github/copilot-instructions.md`
5. Document in `argocd/addons/local/addons.yaml`

## Cluster Fleet Structure

```
argocd/cluster-fleet/
├── spoke1/              # EKS spoke — overrides and instance values
└── local-aws-dev/       # Local Kind cluster
    ├── infrastructure/  # Production KRO CR instances (one file per tier)
    └── tests/           # KRO capability test instances
```

Production CR instances live in `infrastructure/`. Test/validation instances live
in `tests/`. Both are ArgoCD-managed — no manual `kubectl apply`.

## ArgoCD Auto-Sync Configuration (Local CSOC — Test-Verified)

| App | Auto-Sync | Prune | Self-Heal | Effect |
|-----|-----------|-------|-----------|--------|
| `kro-local-rgs-*` (RGDs) | Yes | Yes | Yes | RGD changes auto-sync + self-repair drift |
| `*-infra-instance` (instances) | Yes | Yes | No | Instance YAML changes sync, but no self-heal |

RGD changes flow fully automatically:
`git push` → ArgoCD detects (~3min poll or hard-refresh) → syncs RGD →
KRO reconciles all instances → resources created/updated/deleted.
