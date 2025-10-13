addon-appset
=================

This Helm chart renders an ArgoCD ApplicationSet that deploys addons defined in a central catalog. It's intended to be called by the hub-level ApplicationSet (for example `bootstrap/hub-addons.yaml`) and by other ApplicationSets.

Values to pass (examples):

- hubRepoURL: the git repo URL where `catalog.yaml`, `enablement.yaml` and `values.yaml` live (e.g. the repo's own URL)
- hubRepoRevision: git revision (branch, tag, commit)
- catalogPath: path in the repo to `catalog.yaml` (default: `bootstrap/addons/catalog.yaml`)
- enablementPath: path in the repo to `enablement.yaml` (default: `bootstrap/addons/enablement.yaml`)
- valuesPath: path in the repo to the values file used by addons (default: `bootstrap/addons/values.yaml`)

Example call from a parent ApplicationSet (this is handled in `argocd/bootstrap/hub-addons.yaml`):

When creating the parent Application/Generator that deploys this chart, pass values for `hubRepoURL` and `hubRepoRevision` (or use annotations). The chart will then render the ApplicationSet against that repo.
