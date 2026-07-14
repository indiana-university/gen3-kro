output "ack_csoc_role_arn" {
  description = "ARN of the shared ACK CSOC source role"
  value       = try(aws_iam_role.ack_csoc_source[0].arn, "")
}

output "ack_csoc_role_name" {
  description = "Name of the shared ACK CSOC source role"
  value       = try(aws_iam_role.ack_csoc_source[0].name, "")
}

output "argocd_self_managed_role_arn" {
  description = "ARN of the self-managed Argo CD role"
  value       = try(aws_iam_role.argocd_self_managed[0].arn, "")
}

output "argocd_self_managed_role_name" {
  description = "Name of the self-managed Argo CD role"
  value       = try(aws_iam_role.argocd_self_managed[0].name, "")
}

output "controller_ready_token" {
  description = "Opaque value for downstream dependency ordering"
  value = join(",", compact([
    var.cluster_name,
    try(aws_iam_role.ack_csoc_source[0].arn, null),
    try(aws_iam_role.argocd_self_managed[0].arn, null),
    try(aws_iam_role.argocd_controller[0].arn, null),
    try(aws_eks_capability.argocd[0].arn, null),
    try(aws_eks_capability.ack[0].arn, null),
    try(aws_eks_capability.kro[0].arn, null)
  ]))
}
