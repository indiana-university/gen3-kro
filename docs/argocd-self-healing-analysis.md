# ArgoCD Sync Policy Configuration

## Decision Summary

| ApplicationSet | selfHeal | prune | Change? |
|----------------|----------|-------|---------|
| `csoc-addons` | **true** | false | **selfHeal: false→true** |
| `ack-cross-acct` | true | true | No change |
| `spoke-addons` | false | false | No change |
| `fleet` | false | true | No change |
| `fleet-workloads` | false | true | No change |

---

## Rationale

### csoc-addons — selfHeal: **true**, prune: **false**
**selfHeal=true:** ACK controllers and KRO are stateless. If a pod is deleted or a Helm value drifts in-cluster, ArgoCD should auto-restore from git without operator intervention.
**prune=false:** Removing a controller chart from git should not auto-delete the running controller and its CRDs. Deletion of AWS-managing controllers requires explicit manual confirmation.

### ack-cross-acct — selfHeal: **true**, prune: **true**
**selfHeal=true:** CARM ConfigMaps, namespaces, and IAMRoleSelectors are purely declarative with no external side effects. Reapplying them is idempotent and instant.
**prune=true:** These are lightweight Kubernetes objects (ConfigMap, Namespace). If removed from git, they should be cleaned up automatically—no expensive AWS resources are affected.

### spoke-addons — selfHeal: **false**, prune: **false**
**selfHeal=false:** These deploy to remote spoke EKS clusters, not CSOC. External Secrets Operator disruption on a spoke breaks all workload secret access. Require operator review before any sync.
**prune=false:** Accidentally deleting ESO from a spoke cluster is catastrophic—workloads lose access to database credentials. Both operations require manual confirmation.

### fleet — selfHeal: **false**, prune: **true**
**selfHeal=false:** KRO instances manage expensive cross-account AWS infrastructure (VPC, EKS, Aurora) with 15–30 minute reconciliation times. Operators need control over when infrastructure changes are applied.
**prune=true:** When a spoke is decommissioned and its KRO instance is removed from git, the corresponding AWS resources should be cleaned up. This is an intentional, reviewed deletion.

### fleet-workloads — selfHeal: **false**, prune: **true**
**selfHeal=false:** Workload applications deploy Gen3 services to spoke clusters. Changes may require coordinated rollouts or database migrations. Manual sync gives operators timing control.
**prune=true:** When a workload is removed from git (e.g., decommissioning a spoke's gen3 deployment), the rendered ArgoCD Application should be deleted so the spoke cluster is cleaned up.
