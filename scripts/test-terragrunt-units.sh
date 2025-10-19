#!/bin/bash
# Script to test terragrunt init and plan for all units
# Uses local module sources via TG_SOURCE_MAP

set -e

# Configuration
export GEN3_KRO_VERSION="jimi-container-terragrunt-remodel"
export TG_SOURCE_MAP="git::git@github.com:indiana-university/gen3-kro.git=/workspaces/gen3-kro"

# Test environment variables (replace with actual test values as needed)
export ACK_SERVICE_NAME="iam"
export SPOKE_ROLE_ARNS="arn:aws:iam::123456789012:role/test-spoke-role-1,arn:aws:iam::123456789013:role/test-spoke-role-2"

UNITS_DIR="/workspaces/gen3-kro/units"
RESULTS_LOG="/workspaces/gen3-kro/terragrunt-test-results.log"

# Clear previous log
> "$RESULTS_LOG"

echo "========================================"
echo "Testing Terragrunt Units"
echo "Version: $GEN3_KRO_VERSION"
echo "========================================"
echo ""

# Function to test a unit
test_unit() {
    local unit_name=$1
    local unit_path="$UNITS_DIR/$unit_name"

    echo "----------------------------------------"
    echo "Testing: $unit_name"
    echo "----------------------------------------"

    cd "$unit_path"

    # Run init
    echo "Running: terragrunt init"
    if terragrunt init --terragrunt-ignore-dependency-errors --terragrunt-log-level warn >> "$RESULTS_LOG" 2>&1; then
        echo "✓ Init successful"
    else
        echo "✗ Init failed (see log)"
        echo "INIT FAILED: $unit_name" >> "$RESULTS_LOG"
        echo "  Check log file for details"
        return 1
    fi

    # Run plan
    echo "Running: terragrunt plan"
    if terragrunt plan --terragrunt-ignore-dependency-errors --terragrunt-log-level warn >> "$RESULTS_LOG" 2>&1; then
        echo "✓ Plan successful"
    else
        echo "✗ Plan failed (see log)"
        echo "PLAN FAILED: $unit_name" >> "$RESULTS_LOG"
        echo "  Check log file for details"
        # Don't return error for plan failures - we want to see all results
    fi

    echo ""
}

# List of units to test (in dependency order)
units=(
    "vpc"
    "eks-cluster"
    "eks-hub"
    "iam-spoke"
    "ack-iam-policy"
    "ack-pod-identity"
    "ack-spoke-role"
    "addons-pod-identities"
    "cross-account-policy"
    "argo-deploy"
)

# Track results
declare -a init_passed
declare -a init_failed
declare -a plan_passed
declare -a plan_failed

# Test each unit
for unit in "${units[@]}"; do
    if test_unit "$unit"; then
        init_passed+=("$unit")
        plan_passed+=("$unit")
    else
        # Check what failed
        if grep -q "INIT FAILED: $unit" "$RESULTS_LOG"; then
            init_failed+=("$unit")
        else
            init_passed+=("$unit")
            if grep -q "PLAN FAILED: $unit" "$RESULTS_LOG"; then
                plan_failed+=("$unit")
            else
                plan_passed+=("$unit")
            fi
        fi
    fi
done

# Summary
echo "========================================"
echo "SUMMARY"
echo "========================================"
echo "Init Passed: ${#init_passed[@]}"
for unit in "${init_passed[@]}"; do
    echo "  ✓ $unit"
done

echo ""
echo "Init Failed: ${#init_failed[@]}"
for unit in "${init_failed[@]}"; do
    echo "  ✗ $unit"
done

echo ""
echo "Plan Passed: ${#plan_passed[@]}"
for unit in "${plan_passed[@]}"; do
    echo "  ✓ $unit"
done

echo ""
echo "Plan Failed: ${#plan_failed[@]}"
for unit in "${plan_failed[@]}"; do
    echo "  ✗ $unit"
done

echo ""
echo "Full logs: $RESULTS_LOG"
echo "========================================"
