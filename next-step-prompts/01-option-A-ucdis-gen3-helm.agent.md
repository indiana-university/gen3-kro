---
title: "Option A — ArgoCD bootstrap in spoke via ACK + uc-cdis/gen3-helm"
source_repo: "https://github.com/uc-cdis/gen3-helm"
intent: "Ensure ArgoCD is installed into each spoke EKS cluster so it can receive and reconcile Application CRs from CSOC. Use uc-cdis/gen3-helm as the upstream chart source. Fork uc-cdis/gen3-helm, add ArgoCD support, and open a PR. In gen3-kro, extend the ClusterResources1 RGD to bootstrap spoke ArgoCD via a CSOC Application."
---

Goal
----
- Install ArgoCD into each spoke EKS cluster as part of the KRO provisioning graph so the spoke can accept and reconcile Application CRs delivered by CSOC.
- Contribute ArgoCD installation support to `uc-cdis/gen3-helm` (upstream fork + PR). `uc-cdis/gen3-helm` is a third-party upstream — changes go through a fork and PR process.

Assumptions
-----------
- The spoke EKS cluster is already registered in CSOC ArgoCD via the `argoCDClusterSecret` created by ClusterResources1.
- IRSA or equivalent credentials are available for ACK controllers (EKS, IAM) on CSOC.
- You have a GitHub account to fork `uc-cdis/gen3-helm` and open a PR.

High-level checklist (ordered)
-----------------------------
1. Fork `uc-cdis/gen3-helm` into your GitHub account and create branch `feature/kro-argocd-bootstrap`.
2. In the forked repo:
   - Add ArgoCD installation support to the `cluster-level-resources` chart. Implement as a new subchart entry (`argocd:`) with `enabled: false` default and values for namespace, server mode, serviceAccount IRSA annotations, and ingress settings.
   - Add a `values-spoke-argocd.yaml` example file with IRSA-friendly defaults for EKS spoke installs.
   - Run `helm lint ./helm/cluster-level-resources` and `helm template gen3-argocd ./helm/cluster-level-resources -f values-spoke-argocd.yaml` to validate rendering.
   - Open a PR to `uc-cdis/gen3-helm` with a clear description noting the CSOC-managed bootstrap use-case.
3. In this repository (`gen3-kro`): update `argocd/charts/resource-groups/templates/07-clusterresources1-rg.yaml` (ClusterResources1 RGD):
   - After the `argoCDClusterSecret` resource, add a new ArgoCD `Application` resource in CSOC that deploys the forked `uc-cdis/gen3-helm` chart (or the accepted upstream chart once merged) to the spoke, enabling the `argocd` subchart via helm parameters.
   - Set `destination.server` to the spoke cluster endpoint (from `computeBridge['eks-cluster-endpoint']`).
   - Inject IRSA role ARN (from `iamBridge['argocd-irsa-arn']` or equivalent) as a helm parameter for the ArgoCD serviceAccount annotation.
   - Add `readyWhen` conditions: Application health is Healthy, sync status is Synced.
4. Add a capability test instance under `argocd/local-kind/test/tests/` that validates the ArgoCD bootstrap Application in a Kind environment.
5. Commit gen3-kro changes on branch `feature/argocd-bootstrap-kro` and open a PR referencing the `uc-cdis/gen3-helm` PR.

Acceptance criteria
-------------------
- `uc-cdis/gen3-helm` PR is created, passes `helm lint`, and includes a working `values-spoke-argocd.yaml`.
- `gen3-kro` ClusterResources1 RGD renders a CSOC Application that installs ArgoCD on the spoke when the RGD instance is applied.
- PR in `gen3-kro` includes test instructions for validating the bootstrap Application renders correctly.

Helpful commands
---------------
```bash
# Fork and clone
gh repo fork uc-cdis/gen3-helm --clone=true
cd gen3-helm
git checkout -b feature/kro-argocd-bootstrap

# Lint & template
helm lint ./helm/cluster-level-resources
helm template gen3-argocd ./helm/cluster-level-resources -f values-spoke-argocd.yaml

# Push and open PR
git add helm/cluster-level-resources/
git commit -m "feat(cluster-level-resources): add optional ArgoCD installation subchart for spoke bootstrap"
git push --set-upstream origin feature/kro-argocd-bootstrap
gh pr create --base main --title "feat: add optional ArgoCD spoke bootstrap support"

# In gen3-kro
cd /workspaces/gen3-kro
git checkout -b feature/argocd-bootstrap-kro
# edit argocd/charts/resource-groups/templates/07-clusterresources1-rg.yaml
git add argocd/charts/resource-groups/templates/07-clusterresources1-rg.yaml
git commit -m "feat(rgd): add ArgoCD bootstrap Application to ClusterResources1"
git push --set-upstream origin feature/argocd-bootstrap-kro
```

Notes
-----
- Keep the ArgoCD subchart disabled by default (`argocd.enabled: false`) so existing `cluster-level-resources` deployments are unaffected.
- Per-spoke ArgoCD values (IRSA ARN, namespace, ingress settings) should be overridable via `cluster-values.yaml` in the gitops repo.
- This option is viable as an interim fallback while Option B chart changes go through upstream review.
