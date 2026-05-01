---
title: "Option B — CSOC direct management via jayadeyemi/gen3-build"
source_repo: "https://github.com/jayadeyemi/gen3-build"
intent: "Modify the cluster-level-resources chart to support `destinationServer` so CSOC ArgoCD renders and routes child Applications to the spoke. Update gen3-kro RGDs to inject `destinationServer` from the compute bridge. Work directly in jayadeyemi/gen3-build (no fork needed — this is the source repo)."
---

Goal
----
- Allow CSOC ArgoCD to render the `cluster-level-resources` chart locally (in CSOC) and make all generated child Application CRs target the spoke cluster via a `destinationServer` value, eliminating the need to run ArgoCD inside the spoke.
- `jayadeyemi/gen3-build` **is** the working source repo — work directly on a branch there and open a PR.

What was already done (references/gen3-build in this workspace)
---------------------------------------------------------------
The following changes have been made to `references/gen3-build/helm/cluster-level-resources` and should be replicated to the working branch in `jayadeyemi/gen3-build`:

1. **`values.yaml`** — added `destinationServer: ""` with a comment block explaining its purpose and the CSOC-managed use-case.
2. **20 Application templates** — replaced the hardcoded `server: "https://kubernetes.default.svc"` destination with `server: {{ .Values.destinationServer | default "https://kubernetes.default.svc" | quote }}` in all templates that render ArgoCD Application CRs.
3. **5 karpenter-config-resources-*.yaml templates** — wrapped with an `if/else` block:
   - When `karpenter.configuration.enabled=true`: renders an ArgoCD Application CR sourcing from the configuration repo, targeting `destinationServer`.
   - When `karpenter.configuration.enabled=false` (legacy/inline): keeps the existing inline EC2NodeClass + NodePool rendering for backward compatibility.

Remaining work in jayadeyemi/gen3-build
---------------------------------------
1. Apply the above changes to a feature branch (`feature/destinationServer`) in `jayadeyemi/gen3-build`.
2. Run `helm lint ./helm/cluster-level-resources` to confirm no template syntax errors.
3. Run `helm template test ./helm/cluster-level-resources | grep -A2 "destination:"` to verify all Application CRs now use `destinationServer`.
4. Open a PR in `jayadeyemi/gen3-build` with a clear description referencing the gen3-kro report.

Remaining work in this repository (gen3-kro)
---------------------------------------------
5. Modify `argocd/charts/resource-groups/templates/07-clusterresources1-rg.yaml` (ClusterResources1 RGD):
   - Add `helmChartRepoURL` / `helmChartPath` overrides to point at `jayadeyemi/gen3-build` (path: `helm/cluster-level-resources`).
   - Inject `destinationServer` as a helm parameter set from `${computeBridge.data['eks-cluster-endpoint']}`.
   - Change the `gen3-cluster-resources` Application destination to CSOC (server: `https://kubernetes.default.svc`, namespace: `argocd`) so CSOC ArgoCD renders the chart.
6. Add/update local-kind tests to validate the flow in a dev environment.
7. Commit changes on branch `feature/destinationServer-clusterresources` and open a PR.

Acceptance criteria
-------------------
- `jayadeyemi/gen3-build` PR passes `helm lint` and `helm template` validation; all Application CRs include `destinationServer`.
- Karpenter node-config templates render Application CRs (not raw EC2NodeClass/NodePool) when `karpenter.configuration.enabled=true`.
- `gen3-kro` ClusterResources1 RGD passes `destinationServer` from `computeBridge['eks-cluster-endpoint']` to the chart.

Helpful commands
---------------
```bash
# Clone jayadeyemi/gen3-build and create feature branch
git clone https://github.com/jayadeyemi/gen3-build.git
cd gen3-build
git checkout -b feature/destinationServer

# Apply the same diff from references/gen3-build in gen3-kro (or copy manually)
# Then validate:
helm lint ./helm/cluster-level-resources
helm template test ./helm/cluster-level-resources | grep -A2 "destination:"

# Commit
git add helm/cluster-level-resources/
git commit -m "feat(cluster-level-resources): add destinationServer for CSOC-managed spoke deployment"
git push --set-upstream origin feature/destinationServer

# In gen3-kro
cd /workspaces/gen3-kro
git checkout -b feature/destinationServer-clusterresources
# edit argocd/charts/resource-groups/templates/07-clusterresources1-rg.yaml
git add argocd/charts/resource-groups/templates/07-clusterresources1-rg.yaml
git commit -m "feat(rgd): inject destinationServer from computeBridge into ClusterResources1"
git push --set-upstream origin feature/destinationServer-clusterresources
```

Notes
-----
- `destinationServer` defaults to empty string in values.yaml; chart templates fall back to `"https://kubernetes.default.svc"` via the `| default` pipe, preserving backward compatibility for existing in-cluster deployments.
- For CSOC-managed karpenter node configs (Option B), `karpenter.configuration.enabled=true` is required. The gitops configuration repo must contain `{cluster}/karpenter-node-configs/{type}/` directories with the EC2NodeClass and NodePool manifests.
