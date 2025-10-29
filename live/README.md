# Live Environments

Environment-specific Terragrunt stack configurations that orchestrate catalog deployments across cloud providers.

## Purpose

The `live/` directory contains deployable environment definitions organized by cloud provider, region, and environment name. Each environment directory holds:

- **terragrunt.stack.hcl**: Stack orchestration file that invokes Terragrunt units with environment-specific configuration
- **secrets.yaml**: Sensitive configuration (cloud credentials, database passwords, API keys) - **gitignored**
- **secrets-example.yaml**: Template showing required secrets schema
- **README.md**: Environment-specific documentation
- **.terraform.lock.hcl**: Terraform provider version lock file
- **.terragrunt-stack/**: Terragrunt stack cache directory (auto-generated, gitignored)
- Deployment logs are stored in `outputs/logs/terragrunt-*.log` (gitignored)

## Directory Structure

```
live/
├── aws/
│   └── <region>/
│       └── <csoc_alias>/          # Environment name
│           ├── terragrunt.stack.hcl
│           ├── secrets.yaml       # gitignored
│           ├── secrets-example.yaml
│           ├── README.md
│           ├── .terraform.lock.hcl
│           └── .terragrunt-stack/ # gitignored, auto-generated cache
├── azure/
│   └── <region>/
│       └── <csoc_alias>/          # Environment name
│           ├── terragrunt.stack.hcl
│           ├── secrets.yaml       # gitignored
│           ├── secrets-example.yaml
│           ├── README.md
│           ├── .terraform.lock.hcl
│           ├── .terragrunt-stack/ # gitignored, auto-generated cache
│           └── credentials/       # gitignored - Azure service principal JSON files
└── gcp/
    └── <region>/
        └── <csoc_alias>/          # Environment name
            ├── terragrunt.stack.hcl
            ├── secrets.yaml       # gitignored
            ├── secrets-example.yaml
            ├── README.md
            ├── .terraform.lock.hcl
            ├── .terragrunt-stack/ # gitignored, auto-generated cache
            └── credentials/       # gitignored - GCP service account key JSON files
```

## terragrunt.stack.hcl

The stack file is the orchestration heart of each environment. It:

1. **Parses secrets.yaml**: Loads configuration using `yamldecode(file(local.secrets_file))`
2. **Defines locals**: Extracts csoc, spoke, backend, and path configurations
3. **Invokes units**: Calls Terragrunt units (csoc, spokes) with resolved inputs
4. **Builds the terraform configuration**: Assembles the complete Terraform configuration from modules and locals
5. **Manages dependencies**: Ensures csoc deploys before spokes (via dependency graph)

**Key sections:**

### Locals Block

It extracts configuration from `secrets.yaml` into typed local variables and flattens the structure.
It loads the IAM policies for the csoc and spokes and passes them downstream as a string for use in the Terraform configuration.
Partially prepares maps for use in the Terraform configuration.

### Unit Blocks

Calls Terragrunt units with inputs mapped from locals:

```hcl
unit "csoc" {
  source = "${local.units_path}//csoc" # "//" here loads the units directory into the .terragrunt-cache
  path   = "units/csoc" # describes the path to the csoc unit to the stack
  inputs = {
    example_input = local.example_input
  }
}
```

## secrets.yaml Schema

**Critical: This file is gitignored and must be created manually per environment. Example is provided in repository.**

See `live/<provider>/<region>/<csoc_alias>/secrets-example.yaml` for the template in each environment.

## Secrets Layering

**Never commit secrets.yaml to git.** The file is listed in `.gitignore` to prevent accidental exposure.

**Recommended secret management approaches:**

1. **Local development**: Manually copy `secrets-example.yaml` to `live/<provider>/<region>/<csoc_alias>/secrets.yaml` and edit with real values

2. **Production**: Use separate `secrets.yaml` per environment with strict access controls

## Deployment Checklist

Before running `terragrunt apply --all`:

- [ ] Cloud provider CLI authenticated (`aws configure`, `az login`, `gcloud auth login`)
- [ ] `secrets.yaml` created from `secrets-example.yaml` with valid configuration
- [ ] Terraform state backend pre-created:
  - **AWS**: S3 bucket required; DynamoDB table optional but recommended for state locking (specify in `backend.terraform_locks_table`)
  - **Azure**: Storage account + container exist
  - **GCP**: GCS bucket exists
- [ ] IAM permissions granted for Terraform operations (VPC, cluster, IAM role creation)
- [ ] Network prerequisites met (no CIDR conflicts, subnet availability)
- [ ] Review plan output (via `./init.sh plan` from environment directory) before applying

## Common Commands

All commands should be run from the environment directory (e.g., `live/<provider>/<region>/<csoc_alias>/`).
Use the `init.sh` wrapper script from the repository root for recommended workflow.

### Plan Changes

```bash
# Using init.sh wrapper (recommended - logs to outputs/logs/)
cd /workspaces/gen3-kro
./init.sh plan

# Or directly with terragrunt
cd live/<provider>/<region>/<csoc_alias>
terragrunt plan --all
```

### Apply Infrastructure

```bash
# Using init.sh wrapper (recommended - logs to outputs/logs/)
cd /workspaces/gen3-kro
./init.sh apply

# Or directly with terragrunt
cd live/<provider>/<region>/<csoc_alias>
terragrunt apply --all
```

### Show Outputs

```bash
cd live/<provider>/<region>/<csoc_alias>
terragrunt output --all
```

### Destroy Environment

```bash
cd live/<provider>/<region>/<csoc_alias>
terragrunt destroy --all
```

## Multi-Environment Strategy

Organize environments by provider, region, and instance.

**Example structure:**

```
live/aws/<region>/
└── <csoc_alias>/             # Environment
```

Reuse same Terraform catalog; differentiate via `secrets.yaml` configuration.

## State Management

Terragrunt units auto-generate backend configuration pointing to state bucket/container specified in `secrets.yaml`.

**State isolation:**
- Each environment has separate state (e.g., `s3://<bucket>/<csoc_alias>/units/csoc/terraform.tfstate`)
- Units within an environment share the same backend but use different state keys

**State locking:**
- **AWS**: DynamoDB table optional but recommended (specify in `backend.terraform_locks_table` in secrets.yaml)
- **Azure**: Blob lease mechanism (automatic)
- **GCP**: Cloud Storage object locks (automatic)

**Cache directories:**
- `.terragrunt-stack/`: Terragrunt stack cache (auto-generated, gitignored)
- Contains unit dependencies and cached module downloads

See [`terraform/units/README.md`](../terraform/units/README.md) for backend generation details.

---
**Last updated:** 2025-10-28
