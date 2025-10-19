# ArgoCD Manifests

This directory stores the GitOps layer that ArgoCD consumes to bootstrap and operate the Gen3 KRO hub-and-spoke clusters.

- `application-sets/graph-instances.yaml`: Matrix-based `ApplicationSet` that deploys every ACK controller into each cluster based on labels and annotations.
- `bootstrap/`: Hub bootstrap resources. Notable files include:
  - `graph-instances.yaml`: Seeds KRO resource graph definitions.
  - `gen3-instances.yaml`: Registers Gen3 workload instances.
  - `hub-addons.yaml` and `spoke-addons.yaml`: ArgoCD applications for hub/spoke addons and ACK enablement.
  - `addons/`: Catalog, enablement, and Helm values driving addon configuration.
- `hub/`: Hub-cluster specific overlays.
  - `addons/acks.yaml` and `addons/others.yaml`: Helm values for ACK and auxiliary addons.
  - `bootstrap/`: Base ArgoCD applications that install platform components on the hub.
  - `charts/`: Lightweight Helm chart packaging used by the ArgoCD bootstrap release.
  - `shared/` and `values/`: Shared manifests and ACK overrides consumed by templated ApplicationSets.
- `plans/Phase*.md`, `plans/deployment-plan.md`, `plans/Proposal.md`: Step-by-step wave plans documenting the intended ArgoCD rollout order.
- `shared/instances/`: Kustomize base for reusable resource graph instances.
- `spokes/bootstrap/`: ApplicationSet overlays that enable additional addons on spoke clusters.
- `sample.yaml`: Example ArgoCD application bundle kept for reference.

