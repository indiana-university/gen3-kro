output "iam_bindings" {
  description = "Created IAM bindings"
  value = {
    for k, v in module.spoke_roles : k => {
      bindings = v.bindings
    }
  }
}
