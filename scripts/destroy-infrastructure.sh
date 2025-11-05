#!/usr/bin/env bash
set -u

# destroy_infrastructure.sh
# Deletes the ArgoCD bootstrap Application, disables ArgoCD in secrets.yaml files,
# runs ./dev.sh apply --all, disables VPC in secrets.yaml, then runs terraform apply.
# Behavior & assumptions:
# - Assumes kubectl is configured and can access the cluster.
# - Assumes ./dev.sh exists at repo root and is executable.
# - Assumes terraform is installed and that running `terraform -chdir=terraform apply` is the desired action.
# - secrets.yaml files are gitignored; this script will create backups before editing.
# - The ArgoCD Application to delete defaults to 'bootstrap' in namespace 'argocd' but may be overridden
#   with environment variables ARGO_APP and ARGO_NS.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME=$(basename "$0")

ARGO_APP=${ARGO_APP:-bootstrap}
ARGO_NS=${ARGO_NS:-argocd}

LOG() { printf "[%s] %s\n" "$(date -Iseconds)" "$*"; }
ERR() { LOG "ERROR: $*" >&2; }

prompt_yesno() {
  local prompt="$1" default="$2"
  local resp
  while true; do
    read -r -p "$prompt" resp || return 1
    resp=${resp:-$default}
    case "$resp" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]|"") return 1 ;;
      *) echo "Please answer yes or no (y/N)." ;;
    esac
  done
}

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    cp -a "$f" "$f".bak-$(date +%Y%m%d%H%M%S") || return 1
  fi
}

# Delete ArgoCD application and wait a short time for deletion to begin
delete_bootstrap() {
  LOG "Deleting ArgoCD Application '$ARGO_APP' in namespace '$ARGO_NS'..."
  if ! kubectl -n "$ARGO_NS" delete application "$ARGO_APP" --ignore-not-found=false; then
    ERR "Failed to delete ArgoCD Application '$ARGO_APP' (kubectl returned non-zero)."
    return 1
  fi
  return 0
}

# Modify YAML helper: toggles `enabled: true` to `enabled: false` within a named top-level block
# This is a conservative, indentation-aware change (not a full YAML parser).
toggle_enabled_in_block() {
  local file="$1" block_name="$2"
  local tmp
  tmp=$(mktemp)
  awk -v block="$block_name" '
  BEGIN{inblock=0}
  # detect a top-level block line like: block:
  /^[[:space:]]*[^#].*:/ {
    # strip leading whitespace
    key=$1
  }
  {
    if ($0 ~ "^" block ":[[:space:]]*$") { inblock=1; print; next }
    if (inblock==1) {
      # leaving block on new top-level key (no leading space)
      if ($0 ~ "^[^[:space:]]") { inblock=0; print; next }
      # replace 'enabled: true' within block
      if ($0 ~ "^[[:space:]]+enabled:[[:space:]]*true[[:space:]]*$") {
        sub("true","false"); print; next
      }
      # also handle enabled: "true" or enabled: 'true'
      if ($0 ~ "^[[:space:]]+enabled:[[:space:]]*\"?\'?true\"?\'?["]") {
        gsub("true","false"); print; next
      }
      print; next
    }
    print
  }' "$file" > "$tmp" && mv "$tmp" "$file"
}

patch_secrets_disable_argocd() {
  LOG "Searching for secrets.yaml files to disable ArgoCD..."
  local found=0
  while IFS= read -r f; do
    found=1
    LOG "Found secrets file: $f" 
    backup_file "$f"
    # handle simple common cases:
    # - argocd: true  -> argocd: false
    # - argocd_enabled: true -> argocd_enabled: false
    # - argocd:\n  enabled: true  -> change enabled under argocd block
    if grep -qE "^[[:space:]]*argocd[[:space:]]*:[[:space:]]*true" "$f"; then
      sed -i.bak 's/\(^[[:space:]]*argocd[[:space:]]*:[[:space:]]*\)true/\1false/' "$f" || ERR "sed replacement failed on $f"
    fi
    if grep -qE "argocd_enabled[[:space:]]*:[[:space:]]*true" "$f"; then
      sed -i.bak 's/\(argocd_enabled[[:space:]]*:[[:space:]]*\)true/\1false/' "$f" || ERR "sed replacement failed on $f"
    fi
    # more robust block editing for `argocd:` followed by an indented `enabled: true`
    if grep -qE "^[[:space:]]*argocd[[:space:]]*:" "$f"; then
      toggle_enabled_in_block "$f" "argocd"
    fi
    LOG "Patched $f (backup created)."
  done < <(find "$REPO_ROOT" -type f -name 'secrets.yaml' -not -path '*/.terragrunt-cache/*' -print)

  if [[ $found -eq 0 ]]; then
    LOG "No secrets.yaml files found under $REPO_ROOT. Skipping secrets patch." 
  fi
}

patch_secrets_disable_vpc() {
  LOG "Searching for secrets.yaml files to disable VPC..."
  local found=0
  while IFS= read -r f; do
    found=1
    LOG "Found secrets file: $f" 
    backup_file "$f"
    # Set vpc.enabled -> false if present under vpc: block
    if grep -qE "^[[:space:]]*vpc[[:space:]]*:" "$f"; then
      toggle_enabled_in_block "$f" "vpc"
    fi
    # direct flat keys
    if grep -qE "vpc_enabled[[:space:]]*:[[:space:]]*true" "$f"; then
      sed -i.bak 's/\(vpc_enabled[[:space:]]*:[[:space:]]*\)true/\1false/' "$f" || ERR "sed replacement failed on $f"
    fi
    LOG "Patched VPC flags in $f (backup created)."
  done < <(find "$REPO_ROOT" -type f -name 'secrets.yaml' -not -path '*/.terragrunt-cache/*' -print)

  if [[ $found -eq 0 ]]; then
    LOG "No secrets.yaml files found under $REPO_ROOT. Skipping VPC patch." 
  fi
}

run_dev_apply() {
  LOG "Running ./dev.sh apply --all from repo root"
  (cd "$REPO_ROOT" && ./dev.sh apply --all)
  return $?
}

run_terraform_apply() {
  if ! command -v terraform >/dev/null 2>&1; then
    ERR "terraform not found in PATH. Skipping terraform apply."
    return 2
  fi
  LOG "Running 'terraform -chdir=terraform init'"
  (cd "$REPO_ROOT/terraform" && terraform init -input=false) || { ERR "terraform init failed"; return 1; }
  LOG "Running 'terraform -chdir=terraform apply -auto-approve'"
  (cd "$REPO_ROOT/terraform" && terraform apply -auto-approve) || { ERR "terraform apply failed"; return 1; }
  return 0
}

main() {
  LOG "Starting $SCRIPT_NAME"

  # Step 1: delete bootstrap
  if delete_bootstrap; then
    LOG "Delete requested successfully. Waiting 5 minutes to allow cluster to settle..."
    sleep 300
  else
    ERR "Deleting bootstrap app failed."
    if prompt_yesno "Continue with destroy workflow anyway? (y/N): " N; then
      LOG "User chose to continue despite delete failure. Waiting 2 minutes before continuing..."
      sleep 120
    else
      LOG "User chose to stop. Exiting."; exit 1
    fi
  fi

  # Step 2: disable argocd in secrets.yaml
  patch_secrets_disable_argocd

  # Step 3: run dev.sh apply --all
  if run_dev_apply; then
    LOG "dev.sh apply --all completed successfully."
  else
    ERR "dev.sh apply --all failed. Continuing to VPC disable and terraform step (user may need to investigate)."
  fi

  # Step 4: disable VPC flags in secrets.yaml
  patch_secrets_disable_vpc

  # Step 5: run terraform apply
  if run_terraform_apply; then
    LOG "terraform apply finished successfully."
  else
    ERR "terraform apply encountered errors or was skipped. Check output above."
  fi

  LOG "Destroy workflow finished. Review any errors above and check backups (secrets.yaml.bak-*) if something changed unexpectedly."
}

main "$@"
