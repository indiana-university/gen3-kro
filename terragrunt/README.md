# Terragrunt orchestration layer

Terragrunt is the environment entrypoint for this repository. Live stacks read
the ignored environment config, instantiate reusable unit templates from
[`../terraform/catalog/units`](../terraform/catalog/units/README.md), order
dependencies, generate provider/backend files, and keep each concern in separate
Terraform state.

The supported AWS stacks are documented in
[`live/aws`](live/aws/README.md). Use the repository wrapper from the repository
root so generated units, plan artifacts, reports, and logs are handled
consistently:

```bash
bash scripts/terragrunt-stack.sh <stack> <command> [unit]
```

Supported commands are `generate`, `init`, `plan`, `apply`, `destroy`, and
`output`. Always run and review `plan` before an environment-changing command.
An `apply` or `destroy` must be deliberate and environment-specific.

Terragrunt generates `.terragrunt-stack/` and `.terragrunt-cache/` content.
These directories, provider-generated files, state, plans, and `outputs/` are
local artifacts and must never be committed or used as cross-stack dependency
paths.
