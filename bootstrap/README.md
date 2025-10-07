# Bootstrap Scripts Documentation

> Operational automation and tooling for gen3-kro infrastructure

## Overview

This directory contains all operational scripts for managing the gen3-kro infrastructure. The main entry point is the Terragrunt wrapper, which provides a consistent CLI for all infrastructure operations.

## Directory Structure

```
bootstrap/
├── terragrunt-wrapper.sh    # Main CLI for infrastructure operations
└── scripts/
    ├── lib-logging.sh        # Logging library (sourced by other scripts)
    ├── docker-build-push.sh  # Docker image build and push
    ├── version-bump.sh       # Semantic version management
    └── install-git-hooks.sh  # Git hooks installation
```

## Main Scripts

### terragrunt-wrapper.sh

**Purpose**: Main CLI for all Terragrunt/Terraform operations

**Location**: `bootstrap/terragrunt-wrapper.sh`

**Usage**:
```bash
./bootstrap/terragrunt-wrapper.sh <environment> <command> [options]
```

**Commands**:
- `validate` - Validate configuration
- `plan` - Generate execution plan
- `apply` - Apply infrastructure changes
- `destroy` - Destroy infrastructure
- `output` - Show outputs
- `graph` - Generate dependency graph

**Environments**:
- `staging` - Staging environment
- `prod` - Production environment

**Options**:
- `--yes` - Auto-approve (skip confirmations)
- `--verbose` - Enable verbose logging
- `--debug` - Enable debug mode (TF_LOG=DEBUG)

**Examples**:
```bash
# Validate staging configuration
./bootstrap/terragrunt-wrapper.sh staging validate

# Plan staging changes
./bootstrap/terragrunt-wrapper.sh staging plan

# Apply to staging (auto-confirms)
./bootstrap/terragrunt-wrapper.sh staging apply

# Apply to production (requires typing YES)
./bootstrap/terragrunt-wrapper.sh prod apply

# Apply with auto-confirm (use with caution!)
./bootstrap/terragrunt-wrapper.sh staging apply --yes

# Enable verbose logging
./bootstrap/terragrunt-wrapper.sh staging plan --verbose

# Enable debug mode
./bootstrap/terragrunt-wrapper.sh staging plan --debug

# Destroy (requires YES confirmation)
./bootstrap/terragrunt-wrapper.sh staging destroy

# Show outputs
./bootstrap/terragrunt-wrapper.sh prod output
```

**Features**:
- ✅ Auto-confirmation for destructive operations
- ✅ Comprehensive validation (YAML, AWS credentials, tools)
- ✅ Logging to `outputs/logs/terragrunt-*.log`
- ✅ Support for `--yes`, `--verbose`, `--debug` flags
- ✅ Color-coded output
- ✅ Production safeguards (requires YES for apply/destroy)

**Guardrails**:
- **Production confirm**: Requires typing "YES" for apply/destroy
- **Auto-approve**: Use `--yes` flag to skip prompts
- **Plan artifacts**: Saved as `tfplan` in environment directory
- **Logs**: `outputs/logs/terragrunt-<timestamp>.log`

### lib-logging.sh

**Purpose**: Shared logging library for consistent output formatting

**Location**: `bootstrap/scripts/lib-logging.sh`

**Usage**:
```bash
# Source in your script
source "$(dirname "$0")/scripts/lib-logging.sh"

# Or from bootstrap directory
source "${SCRIPT_DIR}/scripts/lib-logging.sh"
```

**Functions**:
```bash
log_info "message"      # [INFO] - General information
log_success "message"   # [SUCCESS] - Operation succeeded
log_warn "message"      # [WARN] - Warning, non-fatal
log_error "message"     # [ERROR] - Error, may exit
log_notice "message"    # [NOTE] - Important notice
log_debug "message"     # [DEBUG] - Debug info (if VERBOSE=1)
```

**Colors**:
- **INFO**: Cyan
- **SUCCESS**: Green
- **WARN**: Yellow
- **ERROR**: Red
- **NOTE**: Blue
- **DEBUG**: Gray

**Example**:
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/lib-logging.sh"

log_info "Starting operation..."
log_success "Operation completed successfully"
log_warn "This is a warning"
log_error "This is an error"
```

### docker-build-push.sh

**Purpose**: Build and push multi-platform Docker images

**Location**: `bootstrap/scripts/docker-build-push.sh`

**Usage**:
```bash
# Build only (no push)
DOCKER_PUSH=false ./bootstrap/scripts/docker-build-push.sh

# Build and push
export DOCKER_PUSH=true
export DOCKER_USERNAME=jayadeyem
export DOCKER_PASSWORD=<your-token>
./bootstrap/scripts/docker-build-push.sh
```

**Environment Variables**:
- `DOCKER_PUSH` - Set to `true` to push (default: `false`)
- `DOCKER_USERNAME` - Docker Hub username
- `DOCKER_PASSWORD` - Docker Hub access token
- `DOCKER_REPO` - Repository name (default: `jayadeyem/gen3-kro`)

**Features**:
- Multi-platform builds (amd64, arm64)
- Automatic version tagging from `.version` file
- Date-based tags: `v{version}-{YYYYMMDD}-g{sha}`
- Latest tag for main branch
- Build caching for faster builds

**Example Output**:
```
[INFO] Building Docker image: gen3-kro
[INFO] Version: 0.0.1
[INFO] Tag: v0.0.1-20251006-g2c21800
[INFO] Push: false
[SUCCESS] Docker image built successfully
```

### version-bump.sh

**Purpose**: Semantic version management

**Location**: `bootstrap/scripts/version-bump.sh`

**Usage**:
```bash
# Bump patch version (0.0.1 → 0.0.2)
./bootstrap/scripts/version-bump.sh patch

# Bump minor version (0.0.1 → 0.1.0)
./bootstrap/scripts/version-bump.sh minor

# Bump major version (0.0.1 → 1.0.0)
./bootstrap/scripts/version-bump.sh major
```

**Features**:
- Reads current version from `.version` file
- Validates semantic version format
- Updates `.version` file
- Git commits with version bump message
- Tags release (optional)

**Example**:
```bash
# Current version: 0.0.1
./bootstrap/scripts/version-bump.sh minor

# New version: 0.1.0
# File updated: .version
# Git commit: "Bump version to 0.1.0"
```

### install-git-hooks.sh

**Purpose**: Install Git hooks for pre-commit validation

**Location**: `bootstrap/scripts/install-git-hooks.sh`

**Usage**:
```bash
./bootstrap/scripts/install-git-hooks.sh
```

**Hooks**:
- **pre-commit**: Validate YAML syntax, check for secrets
- **pre-push**: Run tests (if configured)

**Features**:
- Automatic installation to `.git/hooks/`
- Executable permissions set
- Validation before commits

**Example**:
```bash
./bootstrap/scripts/install-git-hooks.sh
# [SUCCESS] Git hooks installed successfully
```

## Shell Scripting Conventions

### Standard Preamble

All scripts follow this pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
```

**Explanation**:
- `set -e` - Exit on error
- `set -u` - Exit on undefined variable
- `set -o pipefail` - Fail on pipe errors
- `IFS=$'\n\t'` - Safe field splitting

### Path Resolution

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
```

**Always use**:
- `SCRIPT_DIR` - Directory containing the script
- `REPO_ROOT` - Repository root directory

### Logging Pattern

```bash
# Source logging library
source "${SCRIPT_DIR}/scripts/lib-logging.sh"

# Use logging functions
log_info "Starting..."
log_success "Done"
```

### Error Handling

```bash
# Function-level error handling
function do_something() {
    local result
    if ! result=$(command 2>&1); then
        log_error "Command failed: $result"
        return 1
    fi
    log_success "Command succeeded"
    return 0
}

# Script-level error handling
trap 'log_error "Script failed at line $LINENO"' ERR
```

## Common Patterns

### Validation

```bash
# Check required tools
function check_dependencies() {
    local tools=("terraform" "terragrunt" "aws" "kubectl" "helm")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed"
            return 1
        fi
    done
    log_success "All dependencies installed"
}
```

### Configuration Loading

```bash
# Load YAML configuration
function load_config() {
    local config_file="terraform/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    # Validate YAML syntax
    if ! yq eval '.' "$config_file" > /dev/null 2>&1; then
        log_error "Invalid YAML syntax in $config_file"
        return 1
    fi

    log_success "Configuration loaded"
}
```

### AWS Credential Validation

```bash
# Validate AWS credentials
function validate_aws_credentials() {
    local profile="$1"
    log_info "Validating AWS credentials for profile: $profile"

    if ! aws sts get-caller-identity --profile "$profile" &> /dev/null; then
        log_error "AWS credentials invalid for profile: $profile"
        return 1
    fi

    log_success "AWS credentials valid"
}
```

## Process Management

### ⚠️ CRITICAL - Never Kill Terraform Processes

**Why**: Interrupting Terraform/Terragrunt corrupts state files (no DynamoDB locking)

**Rules**:
- **NEVER** use `Ctrl+C` on running Terraform/Terragrunt
- **NEVER** use `kill` or `timeout` commands
- **ALWAYS** wait for natural completion or timeout
- **CHECK** progress every 60 seconds

**If Command Hangs**:
1. Check every 60 seconds for progress
2. Investigate root cause (AWS API limits, network, etc.)
3. Wait for natural timeout or completion
4. Manual intervention by user if absolutely necessary

**Example**:
```bash
# ❌ WRONG - Don't do this!
timeout 300 terragrunt apply

# ✅ CORRECT - Let it run
terragrunt apply
```

## Best Practices

### ✅ Do

- **Use logging functions** for consistent output
- **Validate inputs** before executing
- **Check dependencies** at script start
- **Use absolute paths** to avoid confusion
- **Add help text** (`--help` flag)
- **Test in staging** before production
- **Document scripts** with comments

### ❌ Don't

- **DON'T hardcode paths** - use variables
- **DON'T ignore errors** - always check return codes
- **DON'T skip validation** - verify before executing
- **DON'T use `sudo`** unless absolutely necessary
- **DON'T commit secrets** - use environment variables
- **DON'T kill processes** - wait for completion

## Debugging

### Enable Verbose Mode

```bash
# Set in script
set -x  # Print commands before execution

# Or run with bash -x
bash -x ./bootstrap/terragrunt-wrapper.sh staging plan
```

### Check Logs

```bash
# View latest log
tail -f outputs/logs/terragrunt-*.log

# Search logs
grep ERROR outputs/logs/terragrunt-*.log
```

### Dry Run

Many scripts support dry-run mode:

```bash
# Docker build (no push)
DOCKER_PUSH=false ./bootstrap/scripts/docker-build-push.sh

# Terragrunt plan (no apply)
./bootstrap/terragrunt-wrapper.sh staging plan
```

## Testing

### Manual Testing

```bash
# Test Terragrunt wrapper
./bootstrap/terragrunt-wrapper.sh staging validate
./bootstrap/terragrunt-wrapper.sh staging plan

# Test Docker build
DOCKER_PUSH=false ./bootstrap/scripts/docker-build-push.sh

# Test version bump
./bootstrap/scripts/version-bump.sh patch --dry-run
```

### Integration Testing

```bash
# Full workflow test
./bootstrap/terragrunt-wrapper.sh staging validate
./bootstrap/terragrunt-wrapper.sh staging plan
# Review plan output
# Apply if acceptable
```

## Related Documentation

- [Main README](../README.md)
- [Terragrunt Documentation](../terraform/README.md)
- [CI/CD Pipeline](../.github/README.md)
- [Logging Library](scripts/lib-logging.sh)

---

**Last Updated**: October 7, 2025
**Maintained By**: Indiana University
