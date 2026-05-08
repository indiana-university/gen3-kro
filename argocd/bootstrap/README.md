# Bootstrap

Terraform creates the first `bootstrap` ApplicationSet, which reads this directory. Keep files here as Kubernetes manifests, not Helm values.

| File | Creates |
|------|---------|
| `csoc-controllers.yaml` | Controller ApplicationSets from `csoc/controllers` |
| `csoc-kro.yaml` | Recursive `csoc-kro` Application for `csoc/kro` |
| `ack-multi-acct.yaml` | ACK CARM namespaces and IAMRoleSelectors |
| `fleet-instances.yaml` | Per-spoke KRO instance Applications |

Bootstrap pruning is enabled so renamed or removed AppSets are cleaned up by ArgoCD.
