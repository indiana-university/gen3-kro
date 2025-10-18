# Automation Scripts

Utility scripts that support local development and CI tasks.

- `connect-cluster.sh`: Kubeconfig helper that uses AWS IAM Authenticator to attach to the hub cluster.
- `docker-build-push.sh`: Builds the Gen3 KRO container image and pushes it to the configured registry.
- `install-git-hooks.sh`: Installs repository-provided Git hooks into `.git/hooks`.
- `lib-logging.sh`: Shared logging helpers (info/warn/error/success) sourced by other scripts.
- `test-terragrunt-units.sh`: Runs Terragrunt unit tests and reports results.
- `validate-terragrunt.sh`: Formats, validates, and dry-runs Terragrunt stacks.
- `version-bump.sh`: Bumps the application version and updates CHANGELOG-related metadata.

Call these scripts from the repository root unless a script specifies otherwise.

