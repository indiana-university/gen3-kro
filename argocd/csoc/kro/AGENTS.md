# AGENTS.md

## Scope

This tree contains KRO ResourceGraphDefinitions and capability tests. Keep RGDs
as plain YAML; do not Helm-template RGD files.

## RGD Rules

- Use KRO schema DSL fields such as `string | required=true`.
- ACK resources must include region, adoption-policy, and deletion-policy
  annotations.
- ACK `readyWhen` must check both resource identity and
  `ACK.ResourceSynced == True`.
- Use optional chaining and `.orValue()` for status propagation.
- Share cross-RGD values through bridge ConfigMaps and `externalRef`.
- Version breaking schema changes by creating a new RGD kind rather than
  removing or renaming fields in place.

## Safety

Do not commit secrets, real account IDs, ARNs with account IDs, generated
outputs, tfstate, `.terragrunt-stack` content, or local credential artifacts.

