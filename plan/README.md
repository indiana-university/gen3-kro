# CSOC Provisioning Separation Plan

This folder records a repo-level review and a proposed separation of function for
the current Gen3 KRO/CSOC platform.

## Recommendation

Use Terragrunt as the environment orchestrator for CSOC infrastructure,
including IAM, and keep Terraform as the module implementation language.
Split the current CSOC Terraform stack into two primary module concerns:

1. AWS foundation module: VPC, EKS, OIDC, CSOC IAM roles, Secrets Manager access
   policy, and any AWS-managed EKS capability roles. This module should not use
   the Kubernetes or Helm providers.
2. In-cluster bootstrap module: Argo CD namespace/service accounts, Argo CD Helm
   install, repository secrets, cluster/fleet secrets, and the first bootstrap
   ApplicationSet. This module should target a pre-named/pre-created cluster.

After that bootstrap boundary, Argo CD should continue to own controllers,
ResourceGraphDefinitions, multi-account wiring, and per-spoke KRO instances.
KRO plus ACK should continue to model spoke infrastructure and Gen3 application
dependencies.

## Documents

| Document | Purpose |
| --- | --- |
| [repo-assessment.md](repo-assessment.md) | Current-state review of repo structure, languages, tools, coupling points, and risks. |
| [target-operating-model.md](target-operating-model.md) | Proposed ownership boundaries, module layout, execution order, and tool responsibilities. |
| [migration-roadmap.md](migration-roadmap.md) | Step-by-step migration plan with acceptance criteria and rollback notes. |

## Highest-Value Changes

- Move the plain Terraform CSOC environment under Terragrunt orchestration.
- Split AWS-only foundation from in-cluster bootstrap.
- Create direct Terragrunt dependencies between CSOC role creation and spoke IAM
  role trust policies so the spoke role trust can eventually tighten from
  wildcard role-name conditions to exact role ARNs.
- Stop auto-applying infrastructure from devcontainer lifecycle hooks by default.
- Add a schema and layer-specific rendering for `config/shared.auto.tfvars.json`
  or replace it with explicit environment configs.
- Standardize the `infrastructure-values.yaml` spelling across docs, scripts,
  comments, and Helm references.

