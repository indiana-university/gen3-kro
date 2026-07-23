variable "users" {
  description = "Existing IAM users keyed by a stable, non-secret alias. This module never creates or deletes IAM users."
  type = map(object({
    name                      = string
    manage_virtual_mfa        = optional(bool, false)
    mfa_device_name           = optional(string, "")
    attach_assume_role_policy = optional(bool, true)
    assume_role_policy_name   = optional(string, "")
  }))

  validation {
    condition     = alltrue([for user in values(var.users) : trimspace(user.name) != ""])
    error_message = "Every users entry must name an existing IAM user."
  }

  validation {
    condition     = length(distinct([for user in values(var.users) : user.name])) == length(var.users)
    error_message = "Existing IAM user names must be unique across users entries."
  }

  validation {
    condition = length(distinct([
      for user_key, user in var.users :
      user.mfa_device_name
      if user.manage_virtual_mfa && user.mfa_device_name != ""
      ])) == length([
      for user_key, user in var.users :
      user.mfa_device_name
      if user.manage_virtual_mfa && user.mfa_device_name != ""
    ])
    error_message = "Managed virtual MFA device names must be unique."
  }
}

variable "roles" {
  description = "Operator roles keyed by function."
  type = map(object({
    enabled               = optional(bool, true)
    name                  = string
    assigned_user_keys    = optional(set(string), [])
    principal_arns        = optional(set(string), [])
    require_mfa           = optional(bool, true)
    max_session_duration  = optional(number, 43200)
    permissions_policy    = string
    eks_access_policy_arn = optional(string, "")
    allow_spoke_access    = optional(bool, false)
  }))

  validation {
    condition = alltrue([
      for role in values(var.roles) :
      !role.enabled || (
        trimspace(role.name) != "" &&
        role.max_session_duration >= 3600 &&
        role.max_session_duration <= 43200 &&
        can(jsondecode(role.permissions_policy))
      )
    ])
    error_message = "Enabled roles require a name, valid JSON permissions, and a max session duration from 3600 through 43200 seconds."
  }

  validation {
    condition = length(distinct([
      for role in values(var.roles) : role.name if role.enabled
      ])) == length([
      for role in values(var.roles) : role.name if role.enabled
    ])
    error_message = "Enabled operator role names must be unique."
  }

  validation {
    condition = alltrue(flatten([
      for role in values(var.roles) : [
        for user_key in role.assigned_user_keys : contains(keys(var.users), user_key)
      ]
    ]))
    error_message = "Every assigned_user_keys entry must identify a key in users."
  }

  validation {
    condition = alltrue([
      for role in values(var.roles) :
      !role.enabled || length(role.assigned_user_keys) + length(role.principal_arns) > 0
    ])
    error_message = "Every enabled operator role must have an assigned user or explicit principal ARN."
  }

  validation {
    condition = alltrue(flatten([
      for role in values(var.roles) : [
        for arn in role.principal_arns :
        can(regex("^arn:[^:]+:iam::[0-9]{12}:(user|role)/.+$", arn))
      ]
    ]))
    error_message = "principal_arns must contain exact IAM user or role ARNs."
  }
}

variable "default_role_key" {
  description = "Role selected by operator tooling when no explicit role key is supplied."
  type        = string
  default     = "infrastructure-admin"

  validation {
    condition     = contains([for role_key, role in var.roles : role_key if role.enabled], var.default_role_key)
    error_message = "default_role_key must identify an enabled role."
  }
}

variable "tags" {
  description = "Tags applied to managed IAM roles and virtual MFA devices."
  type        = map(string)
  default     = {}
}
