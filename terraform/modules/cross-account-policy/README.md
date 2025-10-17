# Cross-Account Policy Module

This module creates an IAM policy that grants a hub pod identity role permission to assume roles in all configured spoke accounts for a specific ACK controller.

## Purpose

When using ACK (AWS Controllers for Kubernetes) controllers in a hub-and-spoke architecture, the hub cluster needs permission to manage resources in spoke accounts. This module:

1. Accepts a list of spoke role ARNs for a specific ACK service
2. Creates an IAM policy document allowing `sts:AssumeRole` and `sts:TagSession` on those roles
3. Attaches the policy as an inline policy to the hub pod identity role

## Usage

```hcl
module "cross_account_policy" {
  source = "./modules/cross-account-policy"

  service_name                = "ec2"
  hub_pod_identity_role_arn   = module.ack_pod_identity.iam_role_arn

  spoke_role_arns = [
    "arn:aws:iam::111111111111:role/spoke1-ack-ec2-spoke-role",
    "arn:aws:iam::222222222222:role/spoke2-ack-ec2-spoke-role"
  ]

  tags = {
    Environment = "production"
    Service     = "ec2"
  }
}
```

## Integration with Other Modules

This module works in conjunction with:

- **ack-pod-identity**: Provides the hub pod identity role
- **ack-spoke-role**: Creates the spoke roles that this policy grants permission to assume
- **ack-iam-policy**: Provides the ACK service-specific policies

### Typical Workflow

1. Use `ack-iam-policy` to fetch and merge ACK recommended policies
2. Use `ack-pod-identity` to create the hub pod identity role
3. Use this module to grant cross-account assume role permissions
4. Use `ack-spoke-role` (for each spoke) to create assumable roles in spoke accounts

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3 |
| aws | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| create | Whether to create the cross-account policy | `bool` | `true` | no |
| service_name | ACK service name (e.g., 'iam', 'ec2', 'eks') | `string` | n/a | yes |
| hub_pod_identity_role_arn | ARN of the hub pod identity IAM role to attach the policy to | `string` | n/a | yes |
| spoke_role_arns | List of spoke role ARNs that the hub pod identity can assume | `list(string)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| policy_name | Name of the cross-account IAM policy |
| policy_id | ID of the cross-account IAM policy |
| spoke_role_arns | List of spoke role ARNs that can be assumed |
| policy_document | The policy document JSON |
| service_name | ACK service name |
| hub_role_name | Name of the hub IAM role (extracted from ARN) |

## Notes

- The module extracts the role name from the hub pod identity role ARN automatically
- If no spoke role ARNs are provided, the module will not create any resources
- The policy is attached as an inline policy to the hub role, named `ack-{service_name}-cross-account-assume`
- Each ACK controller gets its own cross-account policy, scoped to only the spoke roles for that specific service
- Tags are not currently applied to inline policies (AWS limitation), but are accepted for consistency
