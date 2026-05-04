# gen3-kro - Follow-up Report

**Date:** 2026-05-04
**Scope:** ArgoCD topology, `cluster-level-resources`, and next implementation steps
**Branch:** `main` — HEAD `c7fe271` (gen3-kro), `6bb5247` (gen3-build)

## Summary

Two corrections were necessary:

1. `fleet-instances` applies the spoke KRO instance CRs to the spoke cluster, not to CSOC.
2. Amazon EKS managed ArgoCD is an EKS capability, not an ACK `Addon` CR.

Those two facts make Option A the implemented path and eliminated the need for a separate RGD.

## What is implemented (committed)

### gen3-kro

- **`AwsGen3ClusterResources1`** ([`07-clusterresources1-rg.yaml`](../argocd/charts/resource-groups/templates/07-clusterresources1-rg.yaml)) updated with:
  - `argocdTargetClusterName: string | default=""` schema field — allows overriding the ArgoCD cluster registration name when the spoke is pre-registered under a specific name (e.g. EKS-managed ArgoCD capability).
  - All four cluster-name references (`argoCDClusterSecret.metadata.name`, `stringData.name`, `destination.name`, bridge `argocd-cluster-name` and `argocd-cluster-secret`) made conditional: use `argocdTargetClusterName` when set, fall back to `${name}-spoke` when empty.
  - No separate `AwsGen3ClusterResources2` was created — the single RGD handles both CSOC-ArgoCD and EKS-managed ArgoCD topologies via the override field.

- **`argocd/fleet/spoke1/cluster-level-resources/app.yaml`** ([link](../argocd/fleet/spoke1/cluster-level-resources/app.yaml)):
  - `kind: AwsGen3ClusterResources1`
  - `helmChartRepoURL: "https://github.com/jayadeyemi/Gen3-build.git"`
  - `helmChartPath: "helm/cluster-level-resources"`
  - `helmChartTargetRevision: "main"`

- **`argocd/fleet/spoke1/cluster-level-resources/cluster-values.yaml`** ([link](../argocd/fleet/spoke1/cluster-level-resources/cluster-values.yaml)):
  - `karpenter-crds.default.enabled: true` — explicit, because chart default is now `false`
  - `karpenter-crds.jupyter.enabled: false` — explicit disable
  - `karpenter-crds.workflow.enabled: false` — explicit disable
  - Comments added explaining spoke-owned vs hub-owned mode behavior

- **[`AwsGen3Helm1`](../argocd/charts/resource-groups/templates/08-helm1-rg.yaml)** unchanged — correctly reads `argocd-cluster-name` from `cluster-resources-bridge`.

### gen3-build (`jayadeyemi/Gen3-build`, branch `main`)

- **`helm/cluster-level-resources/values.yaml`**:
  - All Karpenter node profile enables (`default`, `jupyter`, `workflow`, `secondary`, `gpu`) default to `false`. Profiles only render when explicitly enabled in instance values.
  - `destinationServer: ""` added — empty string is backward-compatible (spoke-owned). Set to spoke endpoint for hub-owned mode.
  - `karpenterNodeConfigChart: {repoURL, targetRevision, path}` block added — required only when `destinationServer` is set.

- **`helm/karpenter-node-configs/values.yaml`**: `default.enabled: false` (was `true`).

- **`helm/cluster-level-resources/templates/karpenter-config-resources-{default,jupyter,workflow,secondary,gpu}.yaml`**: Each template branches on `destinationServer` — when set, renders an ArgoCD `Application` CR pointing to `karpenter-node-configs`; when empty, renders raw `EC2NodeClass` + `NodePool` objects directly.

- **`helm/cluster-level-resources/templates/_karpenter-node-config.tpl`**: New helper that renders the Application CR (hub-owned path). Requires `karpenterNodeConfigChart.repoURL`, `.targetRevision`, `.path`.

- **`helm/cluster-level-resources/templates/kube-state-metrics.yaml`**: Hardcoded `https://kubernetes.default.svc` replaced with `{{ .Values.destinationServer | default "https://kubernetes.default.svc" | quote }}`.

## Option A (active)

`Application` CRs for `cluster-level-resources` live in the spoke and are reconciled by the EKS-managed ArgoCD capability there. The capability is created outside KRO via Terraform `aws_eks_capability`. The `AwsGen3ClusterResources1` instance (`app.yaml`) is applied to the spoke by `fleet-instances`; the resulting Application CR therefore lands in the spoke `argocd` namespace.

## Option B (chart-ready, KRO path not implemented)

The chart changes are in place. Option B requires the KRO instance to run on CSOC (not the spoke) so that the `Application` CRs land in CSOC ArgoCD. That requires a separate CSOC-side producer path and is not implemented in this session.

## Pending items (non-live)

| ID | Item | File | Priority |
|----|------|------|----------|
| P1 | `argocdTargetClusterName` not set in `app.yaml` — needed when EKS pre-registers the spoke under a name other than `gen3-spoke`. Verify the registration name from the EKS capability and add the override if it differs. | `argocd/fleet/spoke1/cluster-level-resources/app.yaml` | Before first deploy |
| P2 | `cluster-values.yaml` has no `coreDNS.configuration.coreDnsServiceIP` override. The chart default may not match the spoke cluster's service CIDR. Confirm the correct IP and add it before first sync. | `argocd/fleet/spoke1/cluster-level-resources/cluster-values.yaml` | Before first deploy |
| P4 | `pending.md` P1 — Self-heal policy audit. Not all ArgoCD Applications have `automated.selfHeal: true`. Review which should require manual approval. | `argocd/bootstrap/*.yaml`, ApplicationSet templates | Medium |
| P5 | gen3-build file permission drift — all modified template files show mode `100644→100755`. No content changed. A normalizing commit (`git add --chmod=-x`) cleans this up. | `gen3-build/helm/` templates | Cosmetic |

## Live checks (excluded per scope)

- Verify EKS ArgoCD capability is enabled for spoke1 before wave 27
- Verify spoke ArgoCD project allows the registered spoke cluster name
- Validate `AwsGen3ClusterResources1` transitions to Healthy after first sync
- Monitor first-sync DB job and Fence OIDC credential injection

