################################################################################
# ArgoCD Bootstrap Data Flow
#
# This module owns ArgoCD bootstrap resources that depend on Terraform data:
# - Git credentials retrieval and repository secret
# - CSOC cluster secret metadata used by ApplicationSets/add-ons
################################################################################

################################################################################
# Git Credentials — one Secrets Manager secret per private repo
################################################################################
data "aws_secretsmanager_secret_version" "git_credentials" {
  for_each  = local.managed_repo_secret_names
  secret_id = each.value
}

locals {
  # Historical variable name is ssm_repo_secret_names, but values are AWS
  # Secrets Manager secret IDs. Inputs may be either:
  #   - legacy map: { addons = "/path/to/secret" }
  #   - repo list:  { repos = [{ name = "addons", ssm_secret_name = "/path" }] }
  # Empty entries are ignored so public/no-auth GitOps repositories do not force
  # a plan-time secret read.
  repo_secret_specs = can(var.ssm_repo_secret_names.repos) ? try(tolist(var.ssm_repo_secret_names.repos), []) : []

  repo_secret_names_from_specs = {
    for repo in local.repo_secret_specs :
    trimspace(tostring(try(repo.name, ""))) => trimspace(tostring(try(repo.ssm_secret_name, "")))
    if trimspace(tostring(try(repo.name, ""))) != "" && trimspace(tostring(try(repo.ssm_secret_name, ""))) != ""
  }

  repo_secret_names_from_map = can(var.ssm_repo_secret_names.repos) ? {} : {
    for repo_key, secret_name in tomap(var.ssm_repo_secret_names) :
    trimspace(repo_key) => trimspace(secret_name)
    if trimspace(repo_key) != "" && trimspace(secret_name) != ""
  }

  repo_secret_names         = merge(local.repo_secret_names_from_map, local.repo_secret_names_from_specs)
  managed_repo_secret_names = var.enabled ? local.repo_secret_names : {}

  # Parse each Secrets Manager secret into a map keyed by the logical repo name.
  git_credentials_map = {
    for repo_key, secret_name in local.managed_repo_secret_names : repo_key => {
      data = try(
        jsondecode(data.aws_secretsmanager_secret_version.git_credentials[repo_key].secret_string),
        {}
      )
    }
  }

  git_credentials = {
    for repo_key, entry in local.git_credentials_map : repo_key => {
      githubAppEnterpriseBaseUrl = try(try(entry.data.data, entry.data).githubAppEnterpriseBaseUrl, "")
      githubAppID                = try(try(entry.data.data, entry.data).githubAppID, "")
      githubAppInstallationID    = try(try(entry.data.data, entry.data).githubAppInstallationID, "")
      githubAppPrivateKey        = try(try(entry.data.data, entry.data).githubAppPrivateKey, "")
      type                       = try(try(entry.data.data, entry.data).type, "")
      url                        = try(try(entry.data.data, entry.data).url, "")
    }
  }

  bootstrap_applicationset_manifest_base = yamldecode(file("${path.module}/bootstrap/applicationsets.yaml"))
  bootstrap_applicationset_manifest = merge(
    local.bootstrap_applicationset_manifest_base,
    {
      metadata = merge(
        lookup(local.bootstrap_applicationset_manifest_base, "metadata", {}),
        {
          namespace = var.argocd_namespace
        }
      )
    }
  )

  cluster_secret_name = var.argocd_cluster_secret_name != "" ? var.argocd_cluster_secret_name : "${var.cluster_name}-secret"

  string_labels = {
    for k, v in var.argocd_cluster_labels :
    k => tostring(v)
    if v != null
  }

  string_annotations = {
    for k, v in var.argocd_cluster_annotations :
    k => tostring(v)
    if v != null
  }

  spoke_account_annotations = {
    for alias, account_id in var.spoke_account_ids :
    "${alias}_account_id" => account_id
    if account_id != ""
  }

  extra_annotations = merge(
    # Always present so ACK EKS addon ApplicationSets (missingkey=error) don't
    # fail when the ACK controller role is disabled. Empty means no IRSA.
    {
      ack_controller_role_arn = var.ack_controller_role_arn
      csoc_assume_role_arn    = var.ack_controller_role_arn
    },
    local.spoke_account_annotations,
    # Always present so multi-account ApplicationSet (missingkey=error) doesn't
    # fail when no spoke accounts are configured yet. Empty JSON → no namespaces.
    {
      fleet_spokes_json = length(var.spoke_account_ids) > 0 ? jsonencode(var.spoke_account_ids) : "{}"
    }
  )

  cluster_secret_labels = merge(
    {
      "argocd.argoproj.io/secret-type" = "cluster"
    },
    local.string_labels
  )

  cluster_secret_annotations = merge(local.string_annotations, local.extra_annotations)

}

################################################################################
# Spoke Fleet Cluster Secrets — one per spoke, used as generator rows
# by the fleet ApplicationSet (cluster generator, fleet_member: fleet-spoke-infra).
#
# Each secret registers the spoke as an ArgoCD "cluster" pointing back to the
# in-cluster API server (https://kubernetes.default.svc), so all KRO instance
# objects are applied to the CSOC cluster. The generator iterates these secrets
# to iterate spokes without hard-coding the list in the ApplicationSet YAML.
#
# ACK CARM (namespace annotations) is handled by the multi-account Helm chart
# deployed through ArgoCD bootstrap, NOT by Terraform.
################################################################################
resource "kubernetes_secret_v1" "spoke_fleet" {
  for_each = var.enabled ? var.spoke_account_ids : {}

  metadata {
    name      = "${each.key}-fleet"
    namespace = var.argocd_namespace

    labels = merge(
      {
        "argocd.argoproj.io/secret-type" = "cluster"
        "fleet_member"                   = "fleet-spoke-infra"
        "enable_infra_instances"         = "true"
      },
      # propagate environment/region labels from the CSOC cluster secret
      {
        for k, v in local.string_labels :
        k => v
        if contains(["environment", "aws_region"], k)
      }
    )

    annotations = merge(
      # inherit all repo-URL/basepath annotations from the CSOC cluster secret
      # so the fleet ApplicationSet can read them via {{.metadata.annotations.*}}
      local.string_annotations,
      {
        # per-spoke metadata carried as annotations for ApplicationSet parametrisation
        spoke_alias      = each.key
        spoke_account_id = each.value
      }
    )
  }

  data = {
    name   = each.key
    server = "https://kubernetes.default.svc"
    config = jsonencode({
      tlsClientConfig = { insecure = false }
    })
  }

  type = "Opaque"

  depends_on = [kubernetes_secret_v1.argocd_cluster]
}

################################################################################
# Git Repository Secrets — one Argo CD repo secret per private repo entry
################################################################################
resource "kubernetes_secret_v1" "git_repository" {
  for_each = local.managed_repo_secret_names

  metadata {
    name      = "${each.key}-repo-secret"
    namespace = var.argocd_namespace

    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    githubAppEnterpriseBaseUrl = local.git_credentials[each.key].githubAppEnterpriseBaseUrl
    githubAppID                = local.git_credentials[each.key].githubAppID
    githubAppInstallationID    = local.git_credentials[each.key].githubAppInstallationID
    githubAppPrivateKey        = local.git_credentials[each.key].githubAppPrivateKey
    type                       = local.git_credentials[each.key].type
    url                        = local.git_credentials[each.key].url
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "argocd_cluster" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = local.cluster_secret_name
    namespace = var.argocd_namespace
    labels    = local.cluster_secret_labels

    annotations = local.cluster_secret_annotations
  }

  data = {
    name   = var.cluster_name
    server = "https://kubernetes.default.svc"
    config = jsonencode({
      tlsClientConfig = {
        insecure = false
      }
    })
  }

  type = "Opaque"
}

resource "helm_release" "bootstrap" {
  count     = var.enabled ? 1 : 0
  name      = "gitops-argocd-bootstrap"
  namespace = var.argocd_namespace
  chart     = "${path.module}/bootstrap/chart"
  version   = "1.0.0"

  values = [
    yamlencode({
      bootstrapDependencyToken = var.bootstrap_dependency_token
      resources = [
        yamlencode(local.bootstrap_applicationset_manifest)
      ]
    })
  ]

  depends_on = [
    kubernetes_secret_v1.git_repository, # all repo secrets via for_each
    kubernetes_secret_v1.argocd_cluster
  ]
}
