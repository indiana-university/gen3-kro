# IAM Policies

Cloud provider IAM policy definitions for Gen3 platform controllers and services, organized by provider, cluster, and service type. Currently supports only AWS, Azure, and GCP.
The iam policies in this folder are resource-based policies.
Only default policies are committed to this repository; custom policies must be created per csoc or spoke.
Full access policies are used in default configurations to ensure functionality, but should be restricted in production environments.

## Policy Organization

Policies follow a hierarchical structure with cluster-specific overrides:

```
<iam_base_path>/
├── aws/
│   ├── _default/<addon_name>/inline-policy.json # Default policies for all AWS clusters
│   └── <csoc_alias>/
│       ├── csoc/<addon_name>/inline-policy.json  # Overrides default policy for CSOC
│       └── <spoke_alias>/<addon_name>/inline-policy.json  # Overrides default policy per spoke
├── azure/
│   ├── _default/<addon_name>/role-definition.json # Default policies for all Azure clusters
│   └── <csoc_alias>/
│       ├── csoc/<addon_name>/role-definition.json  # Overrides default policy for CSOC
│       └── <spoke_alias>/<addon_name>/role-definition.json  # Overrides default policy per spoke
└── gcp/
    ├── _default/<addon_name>/role-definition.yaml # Default policies for all GCP clusters
    └── <csoc_alias>/
        ├── csoc/<addon_name>/role-definition.yaml  # Overrides default policy for CSOC
        └── <spoke_alias>/<addon_name>/role-definition.yaml  # Overrides default policy per spoke
```

### Resolution Logic

Terraform modules (specifically `iam-policy`) load policies using this precedence:

1. **Cluster-specific (csoc)**: `<iam_base_path>/<provider>/<csoc_alias>/csoc/<addon_name>/<file>`
2. **Cluster-specific (spoke)**: `<iam_base_path>/<provider>/<csoc_alias>/<spoke_alias>/<addon_name>/<file>`
3. **Default**: `<iam_base_path>/<provider>/_default/<addon_name>/<file>`

If a cluster-specific policy exists, it completely replaces the default (no merging).

**Example resolution** for AWS S3 ACK controller in csoc hub:
- **Check**: `iam/aws/<csoc_alias>/csoc/<addon_name>/inline-policy.json` → exists, use this
- **Fallback** (if not exists): `iam/aws/_default/<addon_name>/inline-policy.json`

**Example resolution** for AWS S3 ACK controller in spoke:
- **Check**: `iam/aws/<csoc_alias>/<spoke_alias>/<addon_name>/inline-policy.json` → exists, use this
- **Fallback** (if not exists): `iam/aws/_default/<addon_name>/inline-policy.json`

## Cluster-Specific Overrides

Use cluster-specific policies to:
- **Restrict permissions for production**: Tighten resource constraints, remove wildcard actions
- **Grant additional permissions for dev/test**: Allow deletion, unrestricted access for experimentation
- **Implement organization policies**: Enforce tagging requirements, restrict regions

**Example: List all unique AWS IAM actions in the default ACK EC2 policy**
```sh
cat /workspaces/gen3-kro/iam/aws/_default/ack-ec2/inline-policy.json | jq -r '.Statement[] | select(.Action | type == "array") | .Action[]' | sort | uniq
```

**Note on file naming conventions:**
- **AWS**: `inline-policy.json`
- **Azure**: `role-definition.json`
- **GCP**: `role-definition.yaml`

## Consumers

IAM policies are referenced by Terragrunt modules based on controller names defined in `addon_configs`.

As long as override_id is not set, roles will be created and policies will be applied from the iam folder

**Example: Hub addon configuration** (from `live/<provider>/<region>/<csoc_alias>/secrets.yaml`):

```yaml
csoc:
  alias: <csoc_alias>
  addon_configs:
    <addon_name>:
      enable_identity: true
      namespace: <namespace>
      service_account: <service_account_name>
spokes:
  - alias: <spoke_alias>
    addon_configs:
      <addon_name>:
        enable_identity: true

```

Terraform module `iam-policy` loads policies for each addon:

```hcl
# In terraform/catalog/combinations/csoc/<provider>/main.tf
module "iam_policies" {
  source = "../../../modules/iam-policy"

  for_each = var.addon_configs  # Iterates over configured addons

  service_name       = each.key  # e.g., "<addon_name>"
  policy_inline_json = file("${path.root}/../../../iam/<provider>/${var.alias}/csoc/${each.key}/inline-policy.json")
}
```

If file doesn't exist at cluster path, module falls back to `_default`.
If the default policy also doesn't exist, the role will be created without any policies attached.
If the files are not properly formatted JSON/YAML, the module will fail with an error during apply.

## Cross-Account Policies

For multi-account/spoke deployments, cross-account permissions are created by the `aws-spoke-role` module.

## Customization Workflows

See [`docs/guides/customization.md`](../docs/guides/customization.md) for detailed guides on:
- Adding new IAM policies for custom controllers
- Modifying existing policies to grant/revoke permissions
- Creating cluster-specific policy variants

---
**Last updated:** 2025-10-28
