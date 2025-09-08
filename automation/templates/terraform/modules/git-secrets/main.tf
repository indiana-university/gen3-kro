resource "kubernetes_secret" "git_secrets" {
  for_each = var.git_secrets

  metadata {
    # you can pick any stable naming; here we hash the SSM path down to 4 chars
    name      = "git-app-${substr(sha256(each.key), 0, 8)}"
    namespace = var.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type                       = "git"
    url                         = lookup(var.integrations, each.key).repo_url
    githubAppEnterpriseBaseUrl  = lookup(var.integrations, each.key).enterprise_base_url
    githubAppID                 = tostring(lookup(var.integrations, each.key).app_id)
    githubAppInstallationID     = tostring(lookup(var.integrations, each.key).installation_id)
    githubAppPrivateKey        = each.value
  }
}

###############################################################################
# 2) **Generated files** – so you can “see what was created”                  #
###############################################################################
resource "local_file" "git_app_key_yaml" {
  for_each = var.git_secrets

  filename = "${path.module}/${var.outputs_dir}/git-app-${substr(sha256(each.key), 0, 8)}-key.yaml"

  content = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "git-app-${substr(sha256(each.key), 0, 8)}-key"
      namespace = var.argocd_namespace
    }
    type       = "Opaque"
    stringData = {
      githubAppPrivateKey = each.value
    }
  })
}

resource "local_file" "git_app_meta_yaml" {
  for_each = var.git_secrets

  filename = "${path.module}/${var.outputs_dir}/git-app-${substr(sha256(each.key), 0, 8)}-meta.yaml"

  content = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "git-app-${substr(sha256(each.key), 0, 8)}-meta"
      namespace = var.argocd_namespace
      labels = {
        "argocd.argoproj.io/secret-type" = "repo-creds"
      }
    }
    stringData = {
      type                       = "git"
      url                        = var.integrations[each.key].repo_url
      githubAppEnterpriseBaseUrl = var.integrations[each.key].enterprise_base_url
      githubAppID                = tostring(var.integrations[each.key].app_id)
      githubAppInstallationID    = tostring(var.integrations[each.key].installation_id)
      githubAppPrivateKeySecret  = jsonencode({
        name = "git-app-${substr(sha256(each.key), 0, 8)}-key"
        key  = "githubAppPrivateKey"
      })
    }
  })
}
