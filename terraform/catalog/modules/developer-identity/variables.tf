###############################################################################
# Variables — Developer Identity Bootstrap
###############################################################################

variable "aws_profile" {
  description = "AWS CLI profile with IAM permissions to create the MFA device and role"
  type        = string
  default     = null
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "iam_user_name" {
  description = "Name of the existing IAM user to attach the MFA device to"
  type        = string
  default     = "Terraform.User"
}

variable "role_name" {
  description = "Name of the devcontainer assume-role"
  type        = string
  default     = "eks-cluster-mgmt-devcontainer"
}

variable "role_max_session_duration" {
  description = "Maximum session duration (seconds) when assuming the role. Default 12 hours."
  type        = number
  default     = 43200
}

variable "mfa_device_name" {
  description = "Name for the virtual MFA device"
  type        = string
  default     = "Terraform.User-virtual-mfa"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Module    = "developer-identity"
    Project   = "eks-cluster-mgmt"
  }
}

variable "terraform_state_bucket" {
  description = "S3 bucket used for Terraform state (for scoping S3 permissions). Leave empty to allow all buckets."
  type        = string
  default     = ""
}

variable "terraform_state_locks_table" {
  description = "DynamoDB table used for Terraform state locking. Leave empty to skip DynamoDB permissions."
  type        = string
  default     = ""
}

variable "outputs_dir" {
  description = "Directory to write output files (MFA setup script, AWS profile config)"
  type        = string
  default     = ""
}

variable "create_virtual_mfa" {
  description = "Whether to create a virtual MFA device. Set false to skip MFA creation and outputs."
  type        = bool
  default     = true
}

variable "attach_user_policy" {
  description = "Whether to attach an IAM policy to the user allowing sts:AssumeRole to the created role."
  type        = bool
  default     = true
}

variable "policy_filename" {
  description = "Filename under iam/developer-identity/ to read the role inline policy JSON from. Leave empty to use default inline policy."
  type        = string
  default     = "gen3-test-developer.json"
}

variable "assume_principal_arns" {
  description = "List of principal ARNs (AWS principals) allowed to assume the role. If empty and iam_user_name is set, that user will be used." 
  type        = list(string)
  default     = []
}

variable "assume_requires_mfa" {
  description = "If true, the role trust policy will require MFA when assuming the role."
  type        = bool
  default     = true
}

variable "inline_policy" {
  description = "Fallback inline policy JSON string to attach to the role when no policy file is provided."
  type        = string
  default     = "{\"Version\": \"2012-10-17\", \"Statement\": [{\"Sid\": \"MinimalIdentity\", \"Effect\": \"Allow\", \"Action\": [\"sts:GetCallerIdentity\",\"sts:GetSessionToken\"], \"Resource\": \"*\"}]}"
}
