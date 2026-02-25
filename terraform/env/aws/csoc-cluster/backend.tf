################################################################################
# S3 Backend — single state file for the entire CSOC environment
#
# Values are injected at `terraform init` via -backend-config flags:
#   terraform init \
#     -backend-config="bucket=<STATE_BUCKET>" \
#     -backend-config="key=<CSOC_ALIAS>/terraform.tfstate" \
#     -backend-config="region=<REGION>"
################################################################################

terraform {
  backend "s3" {
    encrypt = true
  }
}
