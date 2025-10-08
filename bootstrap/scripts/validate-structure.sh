#!/usr/bin/env bash
# Validate new repository structure
set -euo pipefail
IFS=$'\n\t'

# Source logging functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib-logging.sh"

log_info "=== Validating Repository Structure ==="

# Check hub structure
log_info "Checking hub directory structure..."
if [[ -d "hub" ]]; then
    log_info "✓ hub/ directory exists"
    
    # Check terraform structure
    if [[ -d "hub/terraform/live" ]]; then
        log_info "✓ hub/terraform/live/ exists"
    else
        log_warn "✗ hub/terraform/live/ missing"
    fi
    
    # Check argocd structure
    if [[ -d "hub/argocd" ]]; then
        log_info "✓ hub/argocd/ exists"
    else
        log_warn "✗ hub/argocd/ missing"
    fi
else
    log_warn "✗ hub/ directory missing (expected during migration)"
fi

# Check spokes structure
log_info "Checking spokes directory structure..."
if [[ -d "spokes" ]]; then
    log_info "✓ spokes/ directory exists"
    
    for spoke in spokes/*/; do
        if [[ -d "$spoke" ]]; then
            spoke_name=$(basename "$spoke")
            log_info "  Checking spoke: $spoke_name"
            
            if [[ -d "${spoke}infrastructure/base" ]]; then
                log_info "    ✓ infrastructure/base exists"
            else
                log_warn "    ✗ infrastructure/base missing"
            fi
            
            if [[ -d "${spoke}argocd/base" ]]; then
                log_info "    ✓ argocd/base exists"
            else
                log_warn "    ✗ argocd/base missing"
            fi
        fi
    done
else
    log_warn "✗ spokes/ directory missing (expected during migration)"
fi

# Check shared structure
log_info "Checking shared directory structure..."
if [[ -d "shared/kro-rgds" ]]; then
    log_info "✓ shared/kro-rgds/ exists"
else
    log_warn "✗ shared/kro-rgds/ missing (expected during migration)"
fi

# Check config structure
log_info "Checking config directory structure..."
if [[ -d "config" ]]; then
    log_info "✓ config/ directory exists"
    
    if [[ -f "config/config.yaml" ]]; then
        log_info "✓ config/config.yaml exists"
    else
        log_warn "✗ config/config.yaml missing"
    fi
else
    log_warn "✗ config/ directory missing (expected during migration)"
fi

# Validate kustomize builds if hub structure exists
if [[ -d "hub/argocd" ]]; then
    log_info "Validating kustomize builds..."
    
    if command -v kustomize &> /dev/null; then
        # Hub bootstrap
        if [[ -f "hub/argocd/bootstrap/base/kustomization.yaml" ]]; then
            if kustomize build hub/argocd/bootstrap/base > /dev/null 2>&1; then
                log_info "✓ hub/argocd/bootstrap/base builds successfully"
            else
                log_error "✗ hub/argocd/bootstrap/base build failed"
            fi
        fi
        
        # Hub addons
        for addon in hub/argocd/addons/*/base; do
            if [[ -f "$addon/kustomization.yaml" ]]; then
                addon_name=$(basename $(dirname "$addon"))
                if kustomize build "$addon" > /dev/null 2>&1; then
                    log_info "✓ $addon builds successfully"
                else
                    log_error "✗ $addon build failed"
                fi
            fi
        done
    else
        log_warn "kustomize not found, skipping kustomize validation"
    fi
fi

# Validate helm charts if they exist
if [[ -d "hub/argocd/charts" ]]; then
    log_info "Validating helm charts..."
    
    if command -v helm &> /dev/null; then
        for chart in hub/argocd/charts/*/; do
            if [[ -f "$chart/Chart.yaml" ]]; then
                chart_name=$(basename "$chart")
                if helm template test "$chart" --dry-run > /dev/null 2>&1; then
                    log_info "✓ $chart_name validates successfully"
                else
                    log_error "✗ $chart_name validation failed"
                fi
            fi
        done
    else
        log_warn "helm not found, skipping helm validation"
    fi
fi

log_info "=== Validation Complete ==="
