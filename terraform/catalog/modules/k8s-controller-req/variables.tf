################################################################################
# Input Variables
################################################################################

variable "create" {
  description = "Whether to create controller infrastructure resources"
  type        = bool
  default     = true
}

variable "csoc_controller_configs" {
  description = <<-DESC
    Map of controller configurations. Each entry should contain:
    - namespace: Controller namespace name
    - service_account: Service account name
    - identity_arn: (Optional) Cloud identity ARN/ID (role ARN, client ID, or service account email)
    - identity_type: (Optional) Cloud provider type: aws, azure, or gcp (default: aws)
    - component_label: (Optional) Component label for Kubernetes resources
    - extra_labels: (Optional) Additional labels to apply
    - extra_annotations: (Optional) Additional annotations to apply
  DESC
  type = map(object({
    namespace         = string
    service_account   = string
    identity_arn      = optional(string, "")
    identity_type     = optional(string, "aws")
    component_label   = optional(string, "controller")
    extra_labels      = optional(map(string), {})
    extra_annotations = optional(map(string), {})
  }))
  default = {}
}

variable "controller_spoke_roles" {
  description = <<-DESC
    Map of controller spoke roles for cross-account/subscription/project access.
    Structure: controller_name -> spoke_alias -> cloud-specific identity fields
    Provider-specific fields (use appropriate fields for your cloud):
    - AWS: account_id, role_arn
    - Azure: subscription_id, identity_id, client_id
    - GCP: project_id, service_account_email
    Used to create ConfigMaps with cross-account/subscription/project role mappings
  DESC
  type = map(map(object({
    # AWS fields
    account_id = optional(string, "")
    role_arn   = optional(string, "")

    # Azure fields
    subscription_id = optional(string, "")
    identity_id     = optional(string, "")
    client_id       = optional(string, "")

    # GCP fields
    project_id            = optional(string, "")
    service_account_email = optional(string, "")

    # Common fields
    region = optional(string, "")
  })))
  default = {}
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Common annotations to apply to all resources"
  type        = map(string)
  default     = {}
}
