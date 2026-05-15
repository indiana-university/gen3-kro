# CSOC KRO Manifests

This directory is deployed recursively by the `csoc-kro` ApplicationSet in `argocd/bootstrap/csoc-kro.yaml`.

| Path | Contents |
|------|----------|
| `aws-rgds/gen3/` | Gen3 infrastructure ResourceGraphDefinitions |
| `aws-rgds/test/` | KRO capability test ResourceGraphDefinitions |

Keep RGD files plain YAML; no Helm templating is used in this tree.
