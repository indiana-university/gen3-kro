terraform {
  backend "s3" {
    bucket         = "gen3--envs-4852"
    key            = "gen3--hub/${var.environment}/terraform.tfstate"
    region         = ""
    use_lockfile   = true
    encrypt        = true
  }
}