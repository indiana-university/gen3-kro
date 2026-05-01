# gen3-kro — To Do

**Companion to:** gen3-kro-report-20260504.md
**Audience:** Alan Walsh

Items are grouped by which deployment path they belong to. Complete the "Immediate" section first regardless of the option chosen.

---


---

## Option A — ArgoCD on the spoke (EKS capability integration for spoke direct management)

The goal here is to bootstrap a lightweight ArgoCD instance on the spoke EKS cluster so that it can receive and process the Application CRs that ClusterResources1 delivers. The existing `addons.yaml` ApplicationSet mechanism already knows how to deploy Helm charts to registered clusters via label selectors. ArgoCD itself can be delivered the same way rather than as a manual `helm install`.

- [ ] Add an `argo-cd` addon entry to `addons.yaml` with a selector targeting `fleet_member: spoke`. This causes CSOC ArgoCD to install ArgoCD on any registered spoke cluster automatically, using the same wave and sync pattern as every other addon. The spoke cluster Secret created by ClusterResources1 already carries the `fleet_member: spoke` label — no label change needed.
- [ ] Confirm that the `argo-cd` Helm chart version and values (namespace, server mode, IRSA or service account credentials for the spoke ArgoCD) are defined in `cluster-values.yaml` or a dedicated values file so each spoke can differ if needed.
- [ ] Verify the CSOC ArgoCD `default` project allows the spoke cluster as a destination. If the project has a destination allowlist, add the spoke API endpoint.
- [ ] Verify CoreDNS inline values use the correct service IP for the spoke cluster's service CIDR. The chart hardcodes `10.100.0.10` — confirm this matches the spoke before the first ClusterResources1 sync or override it in `cluster-values.yaml`.
- [ ] Verify CSOC ArgoCD has OCI Helm registry support enabled. The Karpenter CRDs chart sources from `public.ecr.aws/karpenter` — this requires ArgoCD 2.10+ or the `--enable-helm-oci-repositories` flag.
- [ ] Once the spoke ArgoCD is healthy, confirm ClusterResources1 transitions to Healthy and the `cluster-resources-bridge` updates. This unblocks Helm1.

---

## Option B — CSOC direct management (no spoke ArgoCD)

Two coordinated changes are needed: one to the `cluster-level-resources` gen3-helm chart, and one to the ClusterResources1 RGD. The chart change is the upstream contribution candidate.

**gen3-helm `cluster-level-resources` chart changes:**
- [ ] Add `destinationServer: "https://kubernetes.default.svc"` to `values.yaml`. This is the backward-compatible default — existing deployments that run the chart inside the spoke cluster are unaffected.
- [ ] Replace the hardcoded `https://kubernetes.default.svc` destination string in all 21 Application templates with `{{ .Values.destinationServer }}`. The change is mechanical — every template has one occurrence.
- [ ] Wrap the 5 Karpenter node configuration templates (`karpenter-config-resources-default`, `-gpu`, `-jupyter`, `-secondary`, `-workflow`) in ArgoCD Application CRs targeting `{{ .Values.destinationServer }}`. These files currently render raw `EC2NodeClass` and `NodePool` objects that are not Application CRs and are unaffected by the `destinationServer` value — without this change, they would land on the CSOC cluster where Karpenter does not exist.
- [ ] Validate the modified chart with a local `helm template` render against the spoke1 values before pushing.
- [ ] Open a pull request to UC-CDIS gen3-helm with the changes. The backward-compatible default means this is a non-breaking contribution.

**ClusterResources1 RGD changes (`07-clusterresources1-rg.yaml`):**
- [ ] Change the `gen3-cluster-resources` Application destination from the spoke cluster (`name: gen3-spoke`) to the CSOC cluster itself (`server: https://kubernetes.default.svc`, namespace `argocd`). With this change, CSOC ArgoCD renders the cluster-level-resources chart and processes the resulting Application CRs itself, routing each one to the spoke via `destinationServer`.
- [ ] Inject `destinationServer` as a Helm parameter in the ClusterResources1 RGD, populated from `computeBridge['eks-cluster-endpoint']`. This is what causes each child Application CR to target the spoke.

**Shared verification with Option A:**
- [ ] Verify the CSOC ArgoCD `default` project allows the spoke cluster as a destination.
- [ ] Verify CoreDNS service IP matches the spoke cluster CIDR.
- [ ] Verify OCI Helm registry support for Karpenter CRDs.

---

## Other To Dos (independent of option choice)

These items apply once either option's ClusterResources1 is resolved and the gen3 chart is syncing.

- [ ] **`gen3-gen3-helm` is OutOfSync/Missing** — The application targets the spoke cluster (`gen3-spoke`) in the `gen3` namespace. Health is `Missing` because no resources have been deployed yet (no ArgoCD on spoke to accept them; not because of a values error). This resolves when Option A or B is implemented and the spoke can receive Application CRs.
- [ ] **First-sync database job** — On the first gen3 chart sync, a database creation job runs that creates per-service credentials in Secrets Manager. Monitor this job to completion. If it fails (e.g., master password not found), seven services will stay down until it is re-triggered manually.
- [ ] **Fence OIDC credentials** — Fence will start but users cannot log in until OIDC client credentials are added to Secrets Manager and an ExternalSecret is configured to pull them. This is a post-launch step and does not block the initial deployment.

---

*Updated: 2026-05-04 | Branch: main*
