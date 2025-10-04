# terraform {
#   required_version = ">= 1.2"

#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = "~> 5.0"
#     }

#     kubernetes = {
#       source  = "hashicorp/kubernetes"
#       version = "~> 2.0"
#       configuration_aliases = [ kubernetes.dev ]
#     }
        
#     helm = {
#       source  = "hashicorp/helm"
#       version = "~> 3.0"
#       configuration_aliases = [ helm.dev ]
#     }

#     # kubectl = {
#     #   source  = "alekc/kubectl"
#     #   version = "~> 2.0"
#     # }
    
#     kind = {
#       source  = "tehcyx/kind"
#       version = "~> 0.0.0"
#       configuration_aliases = [ kind.dev ]
#     }
#   }
# }
