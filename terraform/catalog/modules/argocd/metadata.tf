################################################################################
# ArgoCD Cluster Secret Output
# Contains public cluster configuration in annotations (role ARNs, namespaces)
# Generates properly formatted multi-document YAML for direct kubectl apply
################################################################################
locals {
  # Format cluster secret as proper YAML without outer yamlencode
  cluster_secret_yaml = <<-EOY
apiVersion: v1
kind: Secret
metadata:
  name: ${local.argocd.metadata.name}
  namespace: ${local.argocd.metadata.namespace}
  labels:
%{for k, v in local.argocd.metadata.labels~}
    ${k}: ${jsonencode(v)}
%{endfor~}
  annotations:
%{for k, v in local.argocd.metadata.annotations~}
    ${k}: ${jsonencode(v)}
%{endfor~}
stringData:
  name: ${local.argocd.stringData.name}
  server: ${local.argocd.stringData.server}
  config: |
    ${indent(4, local.argocd.stringData.config)}
%{if can(local.argocd.stringData["cluster-info"])~}
  cluster-info: |
    ${indent(4, local.argocd.stringData["cluster-info"])}
%{endif~}
EOY
}

resource "local_file" "argo_cluster_secret" {
  count    = var.create && (var.cluster != null) ? 1 : 0
  filename = "${var.outputs_dir}/argo_cluster_secret.yaml"
  content  = local.cluster_secret_yaml

  depends_on = [kubernetes_secret_v1.cluster]
}
