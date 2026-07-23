output "ack_controller_role_arn" {
  description = "ARN of the shared ACK controller source role."
  value       = try(aws_iam_role.ack_csoc_source[0].arn, "")
}

output "ack_controller_role_name" {
  description = "Name of the shared ACK controller source role."
  value       = try(aws_iam_role.ack_csoc_source[0].name, "")
}

output "argocd_controller_role_arn" {
  description = "ARN of the enabled self-managed or AWS-managed Argo CD controller role."
  value = join("", compact([
    try(aws_iam_role.argocd_self_managed[0].arn, null),
    try(aws_iam_role.argocd_controller[0].arn, null)
  ]))
}

output "argocd_controller_role_name" {
  description = "Name of the enabled self-managed or AWS-managed Argo CD controller role."
  value = join("", compact([
    try(aws_iam_role.argocd_self_managed[0].name, null),
    try(aws_iam_role.argocd_controller[0].name, null)
  ]))
}

output "controller_ready_token" {
  description = "Opaque value for downstream dependency ordering."
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
