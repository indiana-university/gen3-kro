# CSOC Controller Values

`values.yaml` defines shared controller settings. The `eks-overrides/` and `kind-overrides/` files only enable controllers and add cluster-type-specific settings.

KRO ResourceGraphDefinitions are not defined here; `argocd/bootstrap/csoc-kro.yaml` deploys `argocd/csoc/kro` recursively.

Generated controller Application names default to the controller key, such as `self-managed-kro` or `ack-rds`.
