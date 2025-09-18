#############################
# Install ESO Helm release
#############################
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  namespace  = var.namespace
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.chart_version

  create_namespace = true

  set = [
    {
    name  = "installCRDs"
    value = "true"
    },
    {
    name  = "serviceAccount.name"
    value = var.service_account
    },
    {
    name  = "serviceAccount.create"
    value = "true"

    }
  ]

}

#############################
# ClusterSecretStore
#############################
resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-ssm"
    }
    spec = {
      provider = {
        aws = {
          service = "ParameterStore"
          region  = var.aws_region
          auth = {
            podIdentity = {}
          }
        }
      }
    }
  }

  depends_on = [helm_release.external_secrets]
}

#############################
# ExternalSecrets for repos
#############################
resource "kubernetes_manifest" "repo_secrets" {
  for_each = var.repos

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "gitops-${each.key}-repo"
      namespace = var.argocd_namespace
      labels = {
        "argocd.argoproj.io/secret-type" = "repository"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = kubernetes_manifest.cluster_secret_store.manifest.metadata.name
      }
      target = {
        name = "gitops-${each.key}-repo"
        template = {
          type = "Opaque"
          data = {
            type                    = "git"
            url                     = each.value.url
            githubAppEnterpriseBaseUrl = each.value.enterprise_base_url
            githubAppID             = tostring(each.value.app_id)
            githubAppInstallationID = tostring(each.value.installation_id)
            githubAppPrivateKey     = "{{ .privateKey }}"
          }
        }
      }
      data = [
        {
          secretKey = "privateKey"
          remoteRef = {
            key = each.value.ssm_path
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.cluster_secret_store]
}
