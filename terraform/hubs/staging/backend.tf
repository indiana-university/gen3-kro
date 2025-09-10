terraform {
  backend "s3" {
    bucket         = "--envs-4852"
    key            = "--hub/staging/terraform.tfstate"
    region         = ""
    use_lockfile   = true
    encrypt        = true
  }
}