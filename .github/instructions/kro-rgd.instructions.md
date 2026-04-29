---
applyTo: "argocd/charts/resource-groups/**,**/*-rg.yaml"
---

# KRO ResourceGraphDefinition Conventions

These rules apply when creating or editing RGD YAML files.

## Schema Declaration

Use the KRO DSL for field types:
```yaml
spec:
  fieldName: string | required=true
  fieldWithDefault: string | default="value"
  count: integer | default=1
  enabled: boolean | default=true
  items: "[]string | required=true"    # array types need quotes
```

## Status Propagation

Use optional chaining with `.orValue()` to avoid nil panics:
```yaml
status:
  someField: ${resource.status.?nested.?field.orValue("loading")}
  someArn: ${resource.status.?ackResourceMetadata.?arn.orValue("loading")}
```

## ACK Resources — readyWhen

Every ACK-managed resource must check **both** ARN presence and sync status:
```yaml
readyWhen:
  - ${resource.status.?ackResourceMetadata.?arn.orValue('null') != 'null'}
  - ${resource.status.?conditions.orValue([]).exists(c, c.type == "ACK.ResourceSynced" && c.status == "True")}
```

For KMS keys, also check enabled state:
```yaml
readyWhen:
  - ${resource.status.?keyID.orValue('null') != 'null'}
  - ${resource.status.?conditions.orValue([]).exists(c, c.type == "ACK.ResourceSynced" && c.status == "True")}
  - ${resource.status.?enabled.orValue(false) == true}
```

## ACK Resources — Required Annotations

Every ACK resource template must include these annotations:
```yaml
metadata:
  annotations:
    services.k8s.aws/region: ${schema.spec.region}
    services.k8s.aws/adoption-policy: ${schema.spec.adoptionPolicy}
    services.k8s.aws/deletion-policy: ${schema.spec.deletionPolicy}
```

The schema should expose corresponding fields with defaults:
```yaml
region: string | default="us-east-1"
adoptionPolicy: string | default="adopt-or-create"
deletionPolicy: string | default="delete"
```

## includeWhen (Conditional Resources)

Use `includeWhen` for optional resources:
```yaml
- id: someResource
  includeWhen:
    - ${schema.spec.someFeatureEnabled == true}
```

**Caution:** KRO silently drops any expression that references an excluded resource —
even with optional chaining + orValue. If a resource references another via `includeWhen`,
ensure all references only co-included resources. See Test 8 findings.

## Resource Dependency Chain

KRO infers dependencies from CEL expressions. Reference a parent resource's
field in a child template to create an implicit dependency:
```yaml
# Child depends on namespace because it references namespace.metadata.name
namespace: ${namespace.metadata.name}
```

## Versioned Naming Convention

RGDs use versioned naming: monolithic = `AwsGen3<Component><Version>Flat`,
modular = `AwsGen3<Component><Version>` (no Flat suffix).

- metadata.name: lowercase, no hyphens (e.g., `awsgen3network1`)
- Kind: CamelCase (e.g., `AwsGen3Network1`)
- Filename: `<lowercase>-rg.yaml` (e.g., `awsgen3network1-rg.yaml`)

The version number enables creating v2, v3 graphs alongside existing ones.

## Cross-Tier Bridge Pattern

Modular RGDs communicate via bridge ConfigMaps (not Secrets). Active graphs
expose exactly one public bridge ConfigMap per RGD.

When a public bridge needs values from conditional resources, keep one public
bridge and gate the bridge value with the same feature flag that controls the
resource. Avoid chained `.orValue()` fallbacks across `includeWhen` boundaries.

```yaml
# Single public bridge
- id: advancedBridge
  template:
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: ${schema.spec.advancedBridgeName}
      namespace: ${schema.spec.namespace}
    data:
      waf-acl-arn: "${infrastructureConfig.data['advanced-waf-enabled'] == 'true' ? wafWebAcl.status.?ackResourceMetadata.?arn.orValue('loading') : ''}"
```

```yaml
# Consumer: reads the canonical bridge name in its own namespace
foundationBridgeName: string | default="foundation-bridge"

- id: foundationBridge
  externalRef:
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: ${schema.spec.foundationBridgeName}
      namespace: ${schema.spec.namespace}
```

Bridge key naming: kebab-case (`vpc-id`, `nat-gateway-id`, `platform-key-arn`).
Access in templates: `${foundationBridge.data['vpc-id']}` (bracket notation for
hyphenated keys).

## RGD Update Behavior (Test-Verified)

### Non-Breaking Changes (fully automatic)

Adding resources, adding schema fields with defaults, modifying templates,
or removing resources are all non-breaking. KRO reconciles all instances
automatically (~15s after ArgoCD syncs). No manual intervention needed.

Default values propagate instantly to existing instances without instance
YAML changes.

### Breaking Changes (blocked by KRO)

Removing or renaming schema spec/status fields triggers:
`cannot update CRD: breaking changes detected: Property X was removed`

The RGD goes **Inactive**. Instances continue running but their finalizer
(`kro.run/finalizer`) blocks deletion.

**Recovery:** patch finalizers → delete instances → delete CRD → KRO
recreates CRD (~10s) → ArgoCD re-syncs instances.

**Best practice:** Never remove fields. Version the RGD (v2) instead.
