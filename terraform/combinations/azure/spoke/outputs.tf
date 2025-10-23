output "role_assignments" {
  description = "Created role assignments"
  value = {
    for k, v in module.spoke_roles : k => {
      id = v.role_assignment_id
    }
  }
}
