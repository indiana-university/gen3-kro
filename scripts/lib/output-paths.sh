#!/usr/bin/env bash

# Callers set OUTPUT_ROOT before sourcing this file. OUTPUT_DATE can be
# overridden for reproducible runs; otherwise UTC keeps grouping consistent.
: "${OUTPUT_ROOT:?OUTPUT_ROOT must be set before sourcing output-paths.sh}"

OUTPUT_DATE="${OUTPUT_DATE:-$(date -u +%F)}"
DATED_OUTPUT_DIR="${OUTPUT_ROOT}/${OUTPUT_DATE}"
LOG_DIR="$DATED_OUTPUT_DIR"
REPORT_DIR="$DATED_OUTPUT_DIR"
TERRAGRUNT_DIR="${DATED_OUTPUT_DIR}/terragrunt"

mkdir -p "$DATED_OUTPUT_DIR"
