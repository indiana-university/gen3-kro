# Automation Scripts

Shell scripts for common Gen3-KRO operational tasks, including cluster connectivity, container image management, and version control.

## Script Inventory

| Script | Purpose | Inputs | Destructive | Logging |
|--------|---------|--------|-------------|---------|
| `connect-cluster.sh` | Configure kubectl and ArgoCD CLI to connect to deployed EKS/AKS/GKE cluster | None (reads secrets.yaml and Kubernetes) | No | `outputs/logs/connect-cluster-*.log` |
| `docker-build-push.sh` | Build and push Docker images to container registry | `IMAGE_NAME`, `IMAGE_TAG`, `REGISTRY` (env vars or args) | Yes (pushes to registry) | `outputs/logs/docker-build-*.log` |
| `version-bump.sh` | Increment semantic version in project files | `[major\|minor\|patch]` (default: `patch`) | Yes (modifies files, creates git tag) | `outputs/logs/version-bump-*.log` |
| `init.sh` | Wrapper for Terragrunt operations (plan, apply, destroy) | `[plan\|apply\|destroy\|validate\|output]` | Yes (apply/destroy modify infrastructure) | `outputs/logs/terragrunt-*.log` |
| `lib-logging.sh` | Shared logging library (sourced by other scripts) | N/A (provides functions) | No | Consumed by other scripts |

## Script Details

### connect-cluster.sh

**Purpose**: Updates `~/.kube/config` with cluster credentials and authenticates ArgoCD CLI.

**Usage:**
```bash
./scripts/connect-cluster.sh
# or with dry-run to see actions without changing kubeconfig:
./scripts/connect-cluster.sh --dry-run
```

**Prerequisites:**
- Cluster deployed via Terragrunt (./init.sh apply must have been run)
- Cloud provider CLI authenticated (AWS CLI, Azure CLI, or gcloud)
- secrets.yaml configured in your stack directory

**Operations performed:**
1. Reads cluster name and region from secrets.yaml
2. Runs provider-specific kubeconfig update command:
   - **AWS**: `aws eks update-kubeconfig --name <cluster> --region <region>`
   - **Azure**: `az aks get-credentials --resource-group <rg> --name <cluster>`
   - **GCP**: `gcloud container clusters get-credentials <cluster> --region <region>`
3. Retrieves ArgoCD admin password from Kubernetes secret
4. Retrieves ArgoCD LoadBalancer URL from Kubernetes service
5. Logs in to ArgoCD CLI: `argocd login <endpoint> --username admin --password <password>`

**Output:**
- Updates `~/.kube/config`
- Writes log to `outputs/logs/connect-cluster-YYYYMMDD-HHMMSS.log`

**Destructive impact:** None (read-only configuration update)

---

### docker-build-push.sh

**Purpose**: Builds Docker images from Dockerfile and pushes to specified container registry (ECR, ACR, GCR, DockerHub).

**Usage:**
```bash
./scripts/docker-build-push.sh <image-name> <tag> <registry>

# Examples:
./scripts/docker-build-push.sh gen3-kro latest 123456789012.dkr.ecr.us-east-1.amazonaws.com
./scripts/docker-build-push.sh gen3-portal v2.1.0 gcr.io/my-project
```

You can preview actions with --dry-run (or -n) which will not run docker build or push but will print what would be done:

```bash
./scripts/docker-build-push.sh --dry-run gen3-kro latest myregistry.example.com
```

**Prerequisites:**
- Docker daemon running
- Registry authentication completed:
  - **AWS ECR**: `aws ecr get-login-password | docker login --username AWS --password-stdin <registry>`
  - **Azure ACR**: `az acr login --name <registry-name>`
  - **GCP GCR**: `gcloud auth configure-docker`

**Operations performed:**
1. Validates inputs (image name, tag, registry URL)
2. Builds Docker image: `docker build -t <registry>/<image>:<tag> .`
3. Pushes to registry: `docker push <registry>/<image>:<tag>`

**Output:**
- Built image: `<registry>/<image>:<tag>`
- Writes log to `outputs/logs/docker-build-YYYYMMDD-HHMMSS.log`

**Destructive impact:** Yes (publishes image to registry, potentially overwriting existing tags)

---

### version-bump.sh

**Purpose**: Increments semantic version numbers in project files and creates git tags.

**Usage:**
```bash
./scripts/version-bump.sh [major|minor|patch]

# Examples:
./scripts/version-bump.sh patch   # 1.2.3 → 1.2.4
./scripts/version-bump.sh minor   # 1.2.3 → 1.3.0
./scripts/version-bump.sh major   # 1.2.3 → 2.0.0
```

Pass `--dry-run` to preview the new version and tag without modifying `.version` or creating a git tag:

```bash
./scripts/version-bump.sh --dry-run
```

**Prerequisites:**
- Git repository with clean working tree (no uncommitted changes)
- Current version tag exists (e.g., `v1.2.3`)

**Operations performed:**
1. Reads current version from git tags
2. Increments version based on argument (default: `patch`)
3. Updates version in project files:
   - `argocd/addons/csoc/catalog.yaml` (addon versions)
   - `argocd/charts/*/Chart.yaml` (Helm chart versions)
4. Commits changes: `git commit -am "Bump version to <new-version>"`
5. Creates annotated git tag: `git tag -a v<new-version> -m "Release v<new-version>"`

**Output:**
- Updated version files
- Git commit and tag
- Writes log to `outputs/logs/version-bump-YYYYMMDD-HHMMSS.log`

**Destructive impact:** Yes (modifies files, creates git commit and tag)

**Rollback:**
```bash
git reset --hard HEAD~1  # Undo commit
git tag -d v<new-version>  # Delete tag
```

---

### init.sh

**Purpose**: Wrapper script for Terragrunt operations with standardized logging and error handling.

**Usage:**
```bash
./init.sh <command> [options]

# Commands:
./init.sh plan       # Generate execution plan
./init.sh apply      # Apply infrastructure changes
./init.sh destroy    # Destroy infrastructure
./init.sh validate   # Validate configuration
./init.sh output     # Show Terragrunt outputs

# Options:
-v, --verbose    # Enable verbose logging
--debug          # Enable Terraform debug logging (TF_LOG=DEBUG)
```

`init.sh` also supports `--dry-run` (or `-n`) which will print the Terragrunt command that would be executed without actually running it. Useful for reviewing commands before running destructive operations such as `apply` or `destroy`.

Example (preview):

```bash
./init.sh --dry-run apply
```

**Prerequisites:**
- Terragrunt installed
- Valid environment configuration in `live/<provider>/<region>/<env>/`
- Cloud provider credentials configured

**Operations performed:**
1. Changes to Terragrunt directory (hardcoded or detected)
2. Runs `terragrunt <command> --all`
3. Captures output to log file

**Output:**
- Writes log to `outputs/logs/terragrunt-YYYYMMDD-HHMMSS.log`

**Destructive impact:**
- `plan`, `validate`, `output`: No (read-only)
- `apply`: Yes (provisions/modifies infrastructure)
- `destroy`: Yes (deletes infrastructure)

---

### lib-logging.sh

**Purpose**: Provides shared logging functions for consistent log formatting across scripts.

**Functions exported:**
- `log_info <message>`: Informational log (green)
- `log_warn <message>`: Warning log (yellow)
- `log_error <message>`: Error log (red)
- `log_debug <message>`: Debug log (gray, only if verbose enabled)

**Usage (in other scripts):**
```bash
source "${SCRIPT_DIR}/lib-logging.sh"

log_info "Starting operation..."
log_warn "Deprecated configuration detected"
log_error "Failed to connect to cluster"
```

**Output format:**
```
[2025-10-26 14:30:45] [INFO] Starting operation...
[2025-10-26 14:30:46] [WARN] Deprecated configuration detected
[2025-10-26 14:30:47] [ERROR] Failed to connect to cluster
```

## Authoring Rules

When creating new scripts:

1. **Use logging library**: Source `lib-logging.sh` and use `log_info`, `log_warn`, `log_error`
2. **Create log directory**: `mkdir -p "$LOG_DIR"` before writing logs
3. **Set log file**: Export `LOG_FILE` variable with timestamped path
4. **Enable strict mode**: `set -euo pipefail` at script start
5. **Provide usage function**: Include `usage()` function with examples
6. **Support dry-run**: Add `--dry-run` flag that previews actions without execution
7. **Validate inputs**: Check required arguments/environment variables before proceeding
8. **Document destructive operations**: Clearly indicate if script modifies infrastructure/registry/git

**Example script template:**
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

source "${SCRIPT_DIR}/lib-logging.sh"

LOG_DIR="${REPO_ROOT}/outputs/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="${LOG_DIR}/my-script-$(date +%Y%m%d-%H%M%S).log"
export LOG_FILE

usage() {
  cat <<EOF
Usage: $(basename "$0") <arg1> [options]

DESCRIPTION:
  Brief description of script purpose.

ARGUMENTS:
  arg1    Required argument description

OPTIONS:
  --dry-run    Preview actions without executing
  -v           Verbose logging

EXAMPLES:
  $(basename "$0") value1
  $(basename "$0") value2 --dry-run
EOF
}

log_info "Script started"
# Script logic...
log_info "Script completed"
```

See [`docs/guides/operations.md`](../docs/guides/operations.md) for operational workflows using these scripts.

---
**Last updated:** 2025-10-28
