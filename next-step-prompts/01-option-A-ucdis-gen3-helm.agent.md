---
title: "Option A - Implemented spoke-owned path"
source_repo: "https://github.com/indiana-university/gen3-kro"
intent: "Document the implemented version2 path for spoke-owned Application CRs using the EKS managed ArgoCD capability model."
---

Status
------
- Implemented in `gen3-kro`.
- The active EKS-spoke graph is now [07-clusterresources2-rg.yaml](../argocd/charts/resource-groups/templates/07-clusterresources2-rg.yaml).
- The spoke1 instance uses `kind: AwsGen3ClusterResources2` in [cluster-level-resources/app.yaml](../argocd/fleet/spoke1/cluster-level-resources/app.yaml).

What this path does
-------------------
- Keeps the relevant `Application` CRs in the spoke cluster.
- Uses the EKS managed ArgoCD capability as the reconciler for those spoke-local `Application` CRs.
- Continues to register the spoke cluster by name and publish that name through `cluster-resources-bridge` for [08-helm1-rg.yaml](../argocd/charts/resource-groups/templates/08-helm1-rg.yaml).

Important constraint
--------------------
- The ArgoCD capability itself is not created by KRO.
- It is still created out-of-band through the EKS capability API / Terraform `aws_eks_capability`.
- This is intentional because no ACK `Capability` CRD exists for ArgoCD.

Validation
----------
```bash
helm template ../gen3-kro/argocd/charts/resource-groups
rg -n "AwsGen3ClusterResources2|argocd-management-mode" ../gen3-kro/argocd/charts/resource-groups/templates
rg -n "kind: AwsGen3ClusterResources2" ../gen3-kro/argocd/fleet/spoke1/cluster-level-resources/app.yaml
```

Follow-up checks
----------------
1. Verify the spoke EKS cluster already has the ArgoCD capability enabled before wave 27 runs.
2. Verify the managed ArgoCD project policy allows the registered spoke cluster name.
3. Verify the CoreDNS service IP in [cluster-values.yaml](../argocd/fleet/spoke1/cluster-level-resources/cluster-values.yaml).
