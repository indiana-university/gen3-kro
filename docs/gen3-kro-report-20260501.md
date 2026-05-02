# gen3-kro Progress Report — Week of April 28, 2026

**Prepared for:** Alan Walsh
**Project:** gen3-kro — EKS Cluster Management Platform
**Goal:** Deploy Gen3 Data Commons on spoke EKS cluster (spoke1, us-east-1)

---

## What Was Accomplished This Week

Five categories of work were completed:

#### 1. **Configuration alignment with the Chicago gitops.**
Cluster-level-resource rgd and gen3-helm rgd were updated to match so gitops uses values files consistent with the UC-CDIS gitops. This required changes to the RGD templates to reference the new values file paths.
Location: [spoke1 folder](https://github.com/indiana-university/gen3-kro/tree/main/argocd/fleet/spoke1)

##### 2. **Configmap values as consolidated input for RGDs**
A new pattern was implemented to use a single ConfigMap as the source of truth for multiple RGDs. This simplifies configuration management and ensures consistency across RGDs that need to reference shared values.
Location: [Infrastructure-values.yaml](https://github.com/indiana-university/gen3-kro/blob/main/argocd/fleet/spoke1/infrastructure/infrastructure-values.yaml)

#### 3. **Bug fixes in the orchestration layer.**
Several subtle defects in the resource graph definitions were identified and resolved.
- The most significant was a KRO framework limitation where conditional resources (configmap bridges) were being silently dropped rather than flagging an error, causing downstream deployments to stall indefinitely. These were fixed by redesigning the affected graph nodes.
- A separate defect in the DNS configuration caused the Route 53 hosted zone lookup to fail permanently due to an incorrect field — this was confirmed through a live test and corrected.

#### 4. **Terraform: EKS logging.**
(As you suspected) EKS auto-mode was found to enable control plane logging to CloudWatch by default, incurring unbudgeted cost. Logging has been explicitly disabled in the Terraform module.

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.15.1"

  # Disabled by assigning empty list (default enables all 5 types)
  enabled_log_types = []

  tags = local.tags
}
```

#### 5. **Documentation and tooling.**
Documentation was updated, obsolete documents were removed, and GitHub Copilot agent customizations were added to assist with future development.

---

## Current Status

All infrastructure tiers are active. The Gen3 application deployment (Helm1 and ClusterResources1) are the remaining step, currently blocked on two items resolving:


### Decision Required: Cluster Add-ons Deployment Mode

Before Gen3 ClusterResources1 can be deployed, a decision is needed on how cluster-level add-ons (load balancer controller, node autoscaler, external secrets, cert-manager) are managed for the spoke. In both options below, the intended Kubernetes workloads still run in the spoke cluster. The difference is where the ArgoCD `Application` CRs live and which ArgoCD controller reconciles them.

---

**Option A — Spoke-owned Application CRs**

Each spoke EKS cluster runs its own lightweight ArgoCD instance. CSOC bootstraps or enables that spoke ArgoCD, and the relevant cluster-level resource `Application` CRs live in the spoke and are reconciled there locally.

*Advantages*
- No changes required to the Gen3 Helm charts. This is the deployment model Gen3/UC-CDIS designed, tests, and documents.
- Each spoke is operationally self-contained. If the CSOC management cluster is unreachable, the spoke continues to self-heal its own add-ons.
- Karpenter node configuration resources and other raw manifests fit naturally because spoke ArgoCD is the controller reconciling the spoke-side Application flow.
- Fully compatible with future UC-CDIS upstream chart updates — no divergence to maintain.

*Disadvantages*
- Every spoke requires its own ArgoCD installation to install, upgrade, and secure. At ten spokes, that is ten additional control-plane components to manage.
- Two layers of GitOps to monitor: CSOC ArgoCD for infrastructure, spoke ArgoCD for add-ons. Incidents may require accessing both.
- ArgoCD on each spoke needs its own IAM credentials to pull from ECR and call AWS APIs (~200 MB RAM overhead per spoke, plus IAM setup).
- The spoke ArgoCD must be bootstrapped before the spoke-owned `Application` CRs can reconcile.

---

**Option B — Hub-owned Application CRs**

The hub ArgoCD keeps ownership of the `Application` CRs and manages the spoke remotely. The Gen3 `cluster-level-resources` chart is modified to accept a configurable destination cluster so hub-owned child Applications can target the spoke. The workloads still land in the spoke cluster.

*Advantages*
- A single ArgoCD governs the entire fleet. Add-on versions, configurations, and rollouts are managed from one place across all spokes simultaneously.
- No ArgoCD installation per spoke — less infrastructure, fewer credentials, lower per-spoke RAM and operational overhead.
- Fleet-wide rollouts (e.g., upgrading the ALB controller across all spokes) are a one-line change rather than a spoke-by-spoke operation.
- The chart modification is a candidate for contribution back to the UC-CDIS gen3-helm repository. Because the change uses a defaulted value, it is fully backward-compatible — existing deployments are unaffected and no migration is required.

*Disadvantages*
- Requires a chart change across Application templates in `cluster-level-resources`, plus additional care for Karpenter node configuration files that render raw manifests rather than ArgoCD Application objects.
- The chart changes must be validated and submitted to the Chicago team for review before they can be considered part of the upstream Gen3 release. Until accepted, Indiana University maintains a fork or patch.
- If the CSOC ArgoCD is unavailable, spoke add-ons will drift without self-healing until it recovers.

---

**Recommendation: Option B**

Option B is the better long-term choice for this platform. Managing add-ons from a single control plane is simpler, more consistent, and scales cleanly as spoke count grows. The required chart change is modest and backward-compatible, making it a reasonable contribution to the UC-CDIS gen3-helm project rather than a permanent fork. The plan is to implement and validate the change in gen3-kro, then submit it to the Chicago team for upstream review.

Option A remains viable as an interim fallback — the spoke ArgoCD can be installed manually in a matter of minutes if a decision is needed before the chart changes are ready. The two options are not mutually exclusive during the transition.

---

*Report date: 2026-05-04 | Branch: main | Spoke: spoke1dev.rds-pla.net*
