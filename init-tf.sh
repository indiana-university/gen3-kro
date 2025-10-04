#!/usr/bin/env bash
set -uo pipefail
pushd gen3-kro/terraform/env/prod || exit
rc=0
terraform init -reconfigure
rc=$?
if [[ $rc -eq 0 ]]; then
  terraform plan -input=false -out="../../../../outputs/tf_plan.bin" -var-file="terraform.tfvars"
fi
popd || exit
