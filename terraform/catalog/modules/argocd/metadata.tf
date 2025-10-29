resource "local_file" "argo_metadata" {
  count    = var.create ? 1 : 0
  filename = "${var.outputs_dir}/argo_metadata.yaml"
  content  = yamlencode(try(var.cluster.metadata, {}))
}

