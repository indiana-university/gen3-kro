# Repository Assessment

## Scope Reviewed

Reviewed tracked source under `terraform/`, `terragrunt/`, `argocd/`, `iam/`,
`config/`, `scripts/`, `.devcontainer/`, `docs/`, `.github/`, the root
`Dockerfile`, and repo metadata. The `references/` and `outputs/` directories
were treated as reference/generated material rather than primary source. Ignored
local files that may contain secrets, such as `config/shared.auto.tfvars.json`
and `argocd/spokes/spoke1/secrets.yaml`, were not read.

## Current Functional Boundaries

| Area | Current owner | Notes |
| --- | --- | --- |
| CSOC AWS foundation | Terragrunt unit `csoc_foundation` calling `terraform/catalog/modules/aws-csoc-foundation` | AWS-only boundary for VPC, EKS, OIDC, CSOC IAM roles, and optional AWS-managed capabilities. |
| CSOC IAM roles | Terraform inside `aws-csoc-foundation` | ACK source role and Argo CD role are created before spoke IAM can consume exact role outputs. |
| Spoke workload IAM | Terragrunt unit `spoke_iam` calling `terraform/catalog/modules/aws-spoke` | New CSOC stack passes the exact CSOC source role ARN where available; `terragrunt/live/aws/iam-setup` remains deprecated compatibility. |
| Argo CD install | Terraform module `csoc-in-cluster-bootstrap` | Uses Kubernetes and Helm providers against an existing named cluster. |
| Argo CD bootstrap secrets and ApplicationSet | `argocd-bootstrap` retained as a submodule of `csoc-in-cluster-bootstrap` | Uses Kubernetes and Helm providers, plus `local_file` for connect scripts. |
| Controller deployment | Argo CD | `argocd/bootstrap/csoc-controllers.yaml` drives Helm-rendered ApplicationSets. |
| RGD deployment | Argo CD | Plain YAML under `argocd/csoc/kro`. |
| Spoke infrastructure and Gen3 app path | KRO plus ACK through Argo CD | Per-spoke `kro-aws-instances` values create KRO CRs. |
| Operator runtime | Shell plus devcontainer | Scripts handle MFA, Terraform init/apply/destroy, Kind CSOC, reports, and secrets payload generation. |

## Technology Evaluation

Current toolchain signals from the repo:

| Tool or library | Current signal |
| --- | --- |
| Terraform CLI | `.terraform-version` and Dockerfile pin `1.13.5`; modules allow `>= 1.3.0` or `>= 1.3`. |
| Terragrunt CLI | Dockerfile pins `0.99.1`; stack syntax is already used for IAM. |
| AWS provider | Modules allow `>= 5.0`; lockfile/state artifacts are ignored/generated. |
| Kubernetes and Helm providers | Modules allow Kubernetes `>= 2.20` and Helm `>= 2.9`. |
| AWS EKS module | `terraform-aws-modules/eks/aws` version `21.15.1`. |
| AWS VPC module | `terraform-aws-modules/vpc/aws` version `6.6.0`. |
| EKS pod identity module | `terraform-aws-modules/eks-pod-identity/aws` version `~> 1.4.0`. |
| Kubernetes CLI | Dockerfile pins `kubectl` `1.35.1`. |
| Helm CLI | Dockerfile pins `3.16.1`; local Kind Argo CD chart is pinned to `7.7.16`; Terraform default Argo CD chart is `7.0.0` unless overridden. |
| AWS CLI | Dockerfile pins `2.32.0`. |
| YAML/JSON tooling | `jq` from apt, `yq` `4.44.3`, Python snippets in shell scripts. |
| AI/MCP tooling | `uv/uvx`, Node/npm, VS Code MCP fallback config, and agent guidance under `.github/`. |

| Technology | Keep | Why | Rework needed |
| --- | --- | --- | --- |
| Terraform | Yes | Good fit for reusable AWS and Kubernetes bootstrap modules. | Stop using one composite root for AWS foundation plus in-cluster resources. Add stricter provider locking policy. |
| Terragrunt | Yes, elevate it | Already parses shared config, builds multi-account providers, and manages multiple IAM states. It is the right layer for environment orchestration and dependencies. | Move CSOC foundation and in-cluster bootstrap units under Terragrunt. Keep business resource logic in Terraform modules. |
| Argo CD ApplicationSets | Yes | Existing GitOps chain is clean and matches controller/RGD/fleet ownership. | Keep Terraform to first bootstrap only. Validate cluster secret contract with tests. |
| Helm | Yes | Appropriate for generating ApplicationSets and per-spoke KRO instances. | Avoid spelling drift and add chart rendering validation in CI. |
| KRO | Yes | Encodes Gen3 infrastructure graph and bridge contracts well. | Keep RGDs plain YAML and version breaking schema changes. Improve rollout sequencing docs/tests. |
| ACK | Yes | Fits the cross-account AWS resource model from the CSOC control plane. | Tighten IAM trust after CSOC role creation can precede spoke role creation. |
| Shell scripts | Keep, reduce | Useful for operator entrypoints and reports. | Extract shared credential/config helpers. Avoid duplicating logic between `container-init.sh` and `kind-csoc.sh`. |
| Devcontainer | Keep as toolchain | Provides reproducible CLIs and scoped credential mount. | Do not let lifecycle hooks auto-apply infrastructure by default. Treat it as an operator shell, not the deployment orchestrator. |
| Python snippets | Accept as script internals | Used for report discovery and parsing where shell is awkward. | Keep scripts small or promote shared parsing to a proper helper if it grows. |
| GitHub Copilot/agent metadata | Keep optional | Useful for contributor workflows. | Add actual CI workflows; current `.github/` has instructions/hooks/agents but no workflows. |

## Coupling and Risk Findings

1. The split modules now separate AWS foundation from Kubernetes/Helm bootstrap.
   The legacy `aws-csoc` module remains in-tree for comparison and rollback, but
   the compatibility wrapper uses the new split modules.

2. `csoc-cluster` remains a compatibility wrapper with one state until Phase 3.
   Terragrunt units define the desired split-state layout, but state migration
   still requires AWS-backed planning and deliberate state moves.

3. The new CSOC Terragrunt stack creates foundation before spoke IAM so spoke
   trusts can use the exact CSOC source role ARN. The old account-root plus
   `ArnLike` trust remains only as a compatibility fallback.

4. `config/shared.auto.tfvars.json` is a single human-edited file used by
   Terraform variables, Terragrunt stack evaluation, backend init scripts,
   devcontainer connect logic, and GitOps metadata. The single source is useful,
   but the consumers need narrower typed views.

5. Terraform modules write local workstation artifacts with `local_file`
   resources, including MFA setup instructions and connect scripts. These files
   are operationally useful but should not be part of infrastructure state when
   they can be generated from outputs by scripts.

6. Devcontainer post-create now runs `setup` only. `setup connect` remains on
   post-start for existing clusters and does not apply infrastructure.

7. Credential validation logic is duplicated in `scripts/container-init.sh` and
   `scripts/kind-csoc.sh`.

8. Earlier review found spelling drift around `infrastructure-values.yaml`.
   Active docs, scripts, comments, and Helm references should use that spelling.

9. Provider constraints are broad in modules, while the devcontainer pins exact
   CLI versions. Reproducibility should come from lockfiles and CI, not only a
   local container image.

10. No `.github/workflows` directory is present. There are local guidance files,
    hooks, and skills, but no repository-level validation pipeline.

## Important Existing Strengths

- The Argo CD cluster secret contract is explicit and documented.
- RGDs are kept as plain YAML outside Helm, which reduces template complexity.
- KRO instance values are isolated by spoke.
- The local Kind CSOC reuses the same bootstrap chain for RGD iteration.
- Sensitive local files are broadly covered by `.gitignore`.
- The Terragrunt IAM stack already handles retired spoke provider aliases, which
  is important for safe cleanup of state-bound resources.
