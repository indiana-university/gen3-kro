terraform {
  backend "s3" {
    bucket         = "$APPLICATION_NAME-$DEPLOYMENT_METHOD-envs-4852"
    key            = "$APPLICATION_NAME-$DEPLOYMENT_METHOD-hub/dev/terraform.tfstate"
    region         = "$AWS_REGION"
    use_lockfile   = true
    encrypt        = true
  }
}