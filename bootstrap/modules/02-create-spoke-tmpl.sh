#!/usr/bin/env bash

# Paths (could be configured)
: "${SPOKE_FILE:=${AUTOMATION_DIR}/spokes.env}"
: "${TF_ROOT_DIR:=${TEMPLATES_DIR}/terraform/modules/root}"

create_spoke_templates() {
  local spoke_file="$1"
  local template_dir="$2"

  # Clean up old generated files (matching alias-based naming)
  rm -f "${template_dir}/"spoke-*.tf

  log_info "[create_spoke_templates]: spoke_file=$(realpath --relative-to="$PWD" "$spoke_file"), template_dir=$(realpath --relative-to="$PWD" "$template_dir")"

  if [[ -z "${spoke_file:-}" || -z "${template_dir:-}" ]]; then
    log_error "spoke_file or template_dir is not set"
    return 1
  fi

  if [[ ! -f "$spoke_file" ]]; then
    log_error "Spoke file not found: $spoke_file"
    return 1
  fi

  # Read non-empty, non-comment lines
  mapfile -t SPOKES < <(grep -vE '^\s*#' "$spoke_file" | grep -vE '^\s*$')

  if (( ${#SPOKES[@]} == 0 )); then
    log_error "No valid spoke definitions found in $spoke_file"
    return 1
  fi

  local i=1
  for spoke in "${SPOKES[@]}"; do
    # Expect spoke lines like: alias=<alias> region=<region> profile=<profile>
    local alias=""
    local region=""
    local profile=""
    
    # Break spoke into components
    IFS=' ' read -r -a parts <<< "$spoke"
    for kv in "${parts[@]}"; do
      case $kv in
        alias=*)   alias="${kv#alias=}";;
        region=*)  region="${kv#region=}";;
        profile=*) profile="${kv#profile=}";;
        *) 
          log_error "Unexpected token in spoke definition: ${kv}"
          log "#------------------------------------------------------------------------------------------------------------#"
          return 1;;
      esac
    done

    if [[ -z "$alias" || -z "$region" || -z "$profile" ]]; then
      log_error "Missing alias, region or profile for spoke: $spoke"
      log "#------------------------------------------------------------------------------------------------------------#"
      return 1
    fi

    log_info "Generating spoke: alias=$alias region=$region profile=$profile (index $i)"

    cat > "${template_dir}/spoke-${i}.tf" <<EOT
provider "aws" {
  alias   = "${alias}"
  region  = "${region}"
  profile = "${profile}"
}

module "${alias}" {
  source = "../iam-access"

  ack_services        = var.ack_services
  environment         = var.environment
  hub_account_id      = local.hub_account_id
  cluster_info        = local.cluster_info
  ack_services_config = local.ack_services_config
  tags                = var.tags

  providers = {
    aws.hub   = aws.hub
    aws.spoke = aws.${alias}
  }
}
EOT

    i=$((i + 1))
  done

  log_notice "[create_spoke_templates]: template files generated"
  log "#------------------------------------------------------------------------------------------------------------#"
}

# Main
create_spoke_templates "$SPOKE_FILE" "$TF_ROOT_DIR"
