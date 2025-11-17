################################################################################
# Install ArgoCD
# Note: ArgoCD namespace is created by k8s-controller-req module
################################################################################
resource "helm_release" "argocd" {
  count = var.create && var.install ? 1 : 0

  # https://github.com/argoproj/argo-helm/blob/main/charts/argo-cd/Chart.yaml
  # (there is no offical helm chart for argocd)
  name             = try(var.argocd.name, "argo-cd")
  description      = try(var.argocd.description, "A Helm chart to install the ArgoCD")
  namespace        = "argocd"
  create_namespace = false # Namespace created by k8s-controller-req module
  chart            = try(var.argocd.chart, "argo-cd")
  version          = try(var.argocd.chart_version, "6.6.0")
  repository       = try(var.argocd.repository, "https://argoproj.github.io/argo-helm")
    values         = try(var.argocd.values, [])

  timeout                    = try(var.argocd.timeout, null)
  repository_key_file        = try(var.argocd.repository_key_file, null)
  repository_cert_file       = try(var.argocd.repository_cert_file, null)
  repository_ca_file         = try(var.argocd.repository_ca_file, null)
  repository_username        = try(var.argocd.repository_username, null)
  repository_password        = try(var.argocd.repository_password, null)
  devel                      = try(var.argocd.devel, null)
  verify                     = try(var.argocd.verify, null)
  keyring                    = try(var.argocd.keyring, null)
  disable_webhooks           = try(var.argocd.disable_webhooks, null)
  reuse_values               = try(var.argocd.reuse_values, null)
  reset_values               = try(var.argocd.reset_values, null)
  force_update               = try(var.argocd.force_update, null)
  recreate_pods              = try(var.argocd.recreate_pods, null)
  cleanup_on_fail            = try(var.argocd.cleanup_on_fail, null)
  max_history                = try(var.argocd.max_history, null)
  atomic                     = try(var.argocd.atomic, null)
  skip_crds                  = try(var.argocd.skip_crds, null)
  render_subchart_notes      = try(var.argocd.render_subchart_notes, null)
  disable_openapi_validation = try(var.argocd.disable_openapi_validation, null)
  wait                       = try(var.argocd.wait, true)
  wait_for_jobs              = try(var.argocd.wait_for_jobs, null)
  dependency_update          = try(var.argocd.dependency_update, null)
  replace                    = try(var.argocd.replace, null)
  lint                       = try(var.argocd.lint, null)

  postrender    = try(var.argocd.postrender, null)
  set           = try(var.argocd.set, null)
  set_sensitive = try(var.argocd.set_sensitive, null)
}


################################################################################
# ArgoCD Cluster Info
################################################################################
locals {
  cluster_name = try(var.cluster.name, var.cluster.cluster_name, "in-cluster")
  argocd_labels = merge({
    cluster_name                     = local.cluster_name
    enable_argocd                    = true
    "argocd.argoproj.io/secret-type" = "cluster"
    },
    try(var.cluster.addons, {})
  )
  argocd_annotations = {
    for k, v in try(var.cluster.metadata.annotations, {}) :
    k => (
      # Kubernetes annotations must be strings
      # Convert non-string values to strings, objects to YAML
      can(tostring(v)) && !can(keys(v)) ? tostring(v) : yamlencode(v)
    )
  }
}

locals {
  config = <<-EOT
    {
      "tlsClientConfig": {
        "insecure": false
      }
    }
  EOT
  argocd = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name        = try(var.cluster.secret_name, local.cluster_name)
      namespace   = "argocd"
      annotations = local.argocd_annotations
      labels      = local.argocd_labels
    }
    stringData = merge(
      {
        name   = local.cluster_name
        server = try(var.cluster.server, "https://kubernetes.default.svc")
        config = try(var.cluster.config, local.config)
      },
      try(var.cluster.cluster_info, null) != null ? {
        "cluster-info" = yamlencode(try(var.cluster.cluster_info, {}))
      } : {}
    )
  }
}

resource "kubernetes_secret_v1" "cluster" {
  count = var.create && (var.cluster != null) ? 1 : 0

  metadata {
    name        = local.argocd.metadata.name
    namespace   = local.argocd.metadata.namespace
    annotations = local.argocd.metadata.annotations
    labels      = local.argocd.metadata.labels
  }
  data = local.argocd.stringData

  depends_on = [helm_release.argocd]

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
    ]
  }
}


################################################################################
# Create App of Apps Deployment
################################################################################
resource "helm_release" "bootstrap" {
  for_each = var.create ? var.apps : {}

  name      = each.key
  namespace = "argocd"
  chart     = "${path.module}/charts"
  version   = "1.0.0"

  values = [
    <<-EOT
    resources:
      - ${indent(4, each.value)}
    EOT
  ]

  depends_on = [helm_release.argocd, resource.kubernetes_secret_v1.cluster]
}

###############################################################################
# End of File
###############################################################################
