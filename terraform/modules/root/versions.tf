terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
      configuration_aliases = [ aws.hub, aws.spoke1 ]
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.2"
    }

    kind = {
      source  = "tehcyx/kind"
      version = ">= 0.0.0"
    }
  }
}