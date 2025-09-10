terraform {
  backend "s3" {
    bucket         = "$DESTINATION_REPO-envs-4852"
    key            = "$DESTINATION_REPO-$ENVIRONMENT-hub/staging/terraform.tfstate"
    region         = "$HUB_AWS_REGION"
    use_lockfile   = true
    encrypt        = true
  }
}