---
title: "Option B - Chart work implemented, control-plane refactor still required"
source_repo: "https://github.com/jayadeyemi/Gen3-build"
intent: "Capture what was completed for the future hub-owned path and what is still structurally required in gen3-kro."
---

Completed in `gen3-build`
-------------------------
- Added `destinationServer` to [values.yaml](../../gen3-build/helm/cluster-level-resources/values.yaml).
- Patched the remaining hardcoded child app destinations in `helm/cluster-level-resources/templates/`.
- Added [helm/karpenter-node-configs](../../gen3-build/helm/karpenter-node-configs/) so Karpenter node-config resources can render as child `Application` CRs in a future hub-owned mode.
- Preserved backward compatibility for the existing in-spoke path.

Why Option B is not finished in `gen3-kro`
------------------------------------------
- `fleet-instances` applies the producing KRO instance CRs into the spoke cluster.
- Because of that, [07-clusterresources1-rg.yaml](../argocd/charts/resource-groups/templates/07-clusterresources1-rg.yaml) and [07-clusterresources2-rg.yaml](../argocd/charts/resource-groups/templates/07-clusterresources2-rg.yaml) both create their parent `Application` CRs in the spoke.
- Changing only `spec.destination` on that parent Application does not move ownership to CSOC. It only changes where that spoke-owned parent Application tries to deploy its rendered resources.
- The bridge inputs used by the RGD also live on the spoke, so a real hub-owned producer cannot just be moved by a one-line destination patch.

What a real Option B still needs
--------------------------------
1. A CSOC-side producer path for the parent `cluster-level-resources` Application.
2. Access to the same bridge inputs from CSOC, either by:
   - replicating bridge data into CSOC, or
   - replacing bridge reads with another CSOC-visible source of truth.
3. A decision on whether `AwsGen3Helm1` also remains spoke-owned or is refactored into the same CSOC-side producer model.

Validation already completed
----------------------------
```bash
helm lint ./helm/cluster-level-resources
helm lint ./helm/karpenter-node-configs
helm template test ./helm/cluster-level-resources \
  -f ../gen3-kro/argocd/fleet/spoke1/cluster-level-resources/cluster-values.yaml
```

Conclusion
----------
- The chart-side prerequisites for Option B are in place.
- The remaining work is no longer a `gen3-build` templating task; it is a `gen3-kro` control-plane ownership redesign.
