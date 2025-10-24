# Contributing to the Gen3 KRO Platform

Thank you for investing in the Gen3 KRO platform. The repository is organized to make it easy to extend the CSOC hub, spoke clusters, and the GitOps workflows that deploy them across AWS, Azure, and Google Cloud. This guide explains the modular layout and how to add new capabilities safely.

## Development Environment

- Build or open the dev container (VS Code Dev Containers or `./scripts/docker-build-push.sh`). It downloads the repository, installs Terraform, Terragrunt, ArgoCD CLI, kubectl, and other dependencies so you can start iterating immediately.
- Keep provider credentials outside the repo (environment variables or local profiles). The dev container mounts them when available.
- Run `terragrunt hclfmt`, `terraform fmt`, and `terraform validate` inside the container before submitting work.

## Repository Layout and Modularity

- `.devcontainer/` – Builds the VS Code dev container image with Terraform, Terragrunt, ArgoCD CLI, kubectl, awscli, and helper tooling so every contributor works from the same stack.
- `terraform/combinations/` – Terragrunt entrypoints. `hub/` provisions the AWS CSOC hub (VPC + EKS + ArgoCD). `spoke/` provisions AWS IAM for spoke accounts. Azure and Google Cloud currently rely on KRO graphs instead of Terragrunt compositions; add new combinations here when native Terraform coverage is needed.
- `terraform/modules/` – Reusable AWS-centric Terraform modules (network, EKS, IAM, pod identity, cross-account policy). New hub or spoke capabilities should originate here so they can be shared across combinations.
- `argocd/` – GitOps source of truth. Includes `bootstrap/` ApplicationSets, `addons/` catalogs, `graphs/aws|azure|google/` ResourceGraphDefinitions, and `spokes/` overlays. Extending GitOps behavior happens by adding YAML or Helm assets in this tree.
- `docs/` – Product documentation and runbooks; add onboarding or deep dives alongside this guide.
- `scripts/` – Automation helpers (bootstrap, validation, build routines). Enhance or add scripts when recurring contributor workflows need to be automated.
- `live/` – Environment-specific Terragrunt configuration and state folders. Duplicate or parameterize these directories when onboarding new regions or accounts.

The hub (CSOC) composition seeds AWS ACK controllers today and provides scaffolding for Google Config Connector (KCC) and Azure Service Operator (ASO) through the ArgoCD addon catalog. Spoke compositions stay lightweight and focus on granting the hub the IAM needed to manage AWS workloads; Google and Azure spokes authenticate through controller-managed credentials.

## Adding New Capabilities

### Terraform and Terragrunt

1. Introduce reusable infrastructure in `terraform/modules/NEW_MODULE`.
2. Wire the module into the appropriate combination (`terraform/combinations/hub` or `terraform/combinations/spoke`), adding provider-specific overrides as needed. For new providers, create a sibling combination (for example `terraform/combinations/google`) to keep the code modular.
3. Expose module variables in Terragrunt by updating the relevant `terragrunt.hcl` and, if required, documenting defaults in `live/`.
4. Run `terragrunt validate` or `terraform validate` from the module directory before committing.
5. Capture any opinionated defaults or prerequisites in README.md or provider-specific docs so downstream teams understand how to consume the module.

> AWS Spokes are currently provisioned using KRO controllers. Azure and Google Cloud clusters are can be provisioned through ASO and Googgle KCCs respectively. Add Terraform coverage only when adding new csoc cloud providers.

### Cloud Provider Controllers

1. **AWS ACK (shipping today)** – Add new iam policy under `iam/gen3/csoc/acks/<service>/`, update `ack_configs` in `live/aws/.../config.yaml`, and ensure the hub addon catalog references the desired ACK Helm charts.
2. **Google Config Connector** – Add the controller chart to `argocd/addons/hub/catalog.yaml`, toggle it in `addons/hub/enablement.yaml`, and provide service account JSON or Workload Identity configuration through `addons/hub/values.yaml` or referenced secrets. Resource schemas belong in `argocd/graphs/google/`.
3. **Azure Service Operator** – Mirror the Google workflow: populate the catalog/enablement entries, configure Azure service principal secrets, and create ResourceGraphDefinitions under `argocd/graphs/azure/`.
4. Extend any ApplicationSet templates if a new sync wave or generator is required, and document the behavior so operators know which credentials are expected.

### ArgoCD GitOps Flows

- Each ApplicationSet maps to a branch-driven deployment pipeline. Commit to any branch tracked by the bootstrap ApplicationSet (commonly `main` and `release/*`) to trigger ArgoCD reconciliation.
- When you introduce new workloads or infrastructure graphs, add them to the correct ApplicationSet (hub addons, spoke addons, graphs, graph-instances, or app-instances) so the ArgoCD wave model continues to function.
- Keep clusters and namespaces modular—prefer a new Kustomize overlay under `argocd/spokes/` instead of editing shared bases unless every environment needs the change.
- Document required credentials or Git annotations in the same directory so operators know how to onboard a new cluster.

### KRO Resource Graphs

- Define reusable infrastructure graphs under `argocd/graphs/aws/`, `argocd/graphs/google/`, or `argocd/graphs/azure/` depending on the provider.
- Reference new graphs from `argocd/bootstrap/graphs.yaml` and instantiate them via `argocd/bootstrap/graph-instances.yaml`.
- Keep graph definitions small and composable; prefer multiple focused graphs (network, cluster, database) over a single monolith so spokes can opt in selectively.

### Documentation and Automation

- Add user-facing docs in `docs/`. When the change affects onboarding or architecture, update `README.md` as well.
- Update scripts in `scripts/` if new bootstrap steps are required (for example, seeding secrets or configuring CLIs).

## Contribution Workflow

1. Fork the repository and create a feature branch.
2. Develop inside the dev container to ensure you use the supported toolchain.
3. Validate infrastructure changes with the linting and formatting commands above.
4. For Terraform or Terragrunt updates, capture plan output or testing notes in your pull request.
5. Submit a pull request that explains the motivation, highlights affected providers, and links to any new documentation.

Following these guidelines keeps the CSOC hub, spoke clusters, and GitOps pipelines modular and easy to extend across providers.
