provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = try(base64decode(var.cluster_certificate_authority_data), "")

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = concat(
      [
        "eks",
        "get-token",
        "--cluster-name",
        var.cluster_name,
        "--region",
        var.region,
      ],
      var.aws_profile != "" ? ["--profile", var.aws_profile] : []
    )
  }
}

provider "helm" {
  kubernetes = {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = try(base64decode(var.cluster_certificate_authority_data), "")

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = concat(
        [
          "eks",
          "get-token",
          "--cluster-name",
          var.cluster_name,
          "--region",
          var.region,
        ],
        var.aws_profile != "" ? ["--profile", var.aws_profile] : []
      )
    }
  }
}
