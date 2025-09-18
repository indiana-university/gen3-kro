terraform {
  backend "s3" {
    bucket         = "gen3-kro-envs-4852"
    key            = "gen3-kro-hub/prod/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
}