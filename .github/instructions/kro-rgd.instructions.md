---
description: 'KRO ResourceGraphDefinition conventions, CEL patterns, and ACK resource rules for gen3-kro'
applyTo: "argocd/charts/resource-groups/**,**/*-rg.yaml"
---

# KRO ResourceGraphDefinition Conventions

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

Standard fields every RGD should expose:
```yaml
region: string | default="us-east-1"
adoptionPolicy: string | default="adopt-or-create"
deletionPolicy: string | default="delete"
namespace: string | required=true
name: string | default="gen3"
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

Every ACK resource template must include:
```yaml
metadata:
  annotations:
    services.k8s.aws/region: ${schema.spec.region}
    services.k8s.aws/adoption-policy: ${schema.spec.adoptionPolicy}
    services.k8s.aws/deletion-policy: ${schema.spec.deletionPolicy}
```

## Status Propagation

Use optional chaining with `.orValue()` to avoid nil panics:
```yaml
status:
  someField: ${resource.status.?nested.?field.orValue("loading")}
  someArn: ${resource.status.?ackResourceMetadata.?arn.orValue("loading")}
```

## includeWhen (Conditional Resources)

```yaml
- id: someResource
  includeWhen:
    - ${schema.spec.someFeatureEnabled == true}
```

**Critical:** KRO silently drops any expression referencing an excluded resource,
even with optional chaining + `orValue`. Use the Test 8 dual-resource pattern
for any value that must exist whether or not the conditional resource is included:
create two resources with opposite `includeWhen` conditions, both writing to the
same output key.

**Test 6 finding:** KRO cannot add conditional entries within a single array
(e.g., `ingressRules`). Use Pattern A — multiple separate ACK resources, one per
tier, each with its own `includeWhen`.

## Resource Dependency Chain

KRO infers dependencies from CEL expressions. Reference a parent resource's
field in a child template to create an implicit dependency:
```yaml
# Child depends on namespace because it references namespace.metadata.name
namespace: ${namespace.metadata.name}
```

## Cross-RGD Bridge Pattern (Test 7)

Share values between RGDs via a ConfigMap (bridge) and an `externalRef`:
```yaml
# Producer: write bridge ConfigMap
- id: foundationBridge
  template:
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: foundation-bridge
      namespace: ${schema.spec.namespace}
    data:
      vpcId: ${vpc.status.?vpcID.orValue("")}
      vpcArn: ${vpc.status.?ackResourceMetadata.?arn.orValue("")}

# Consumer: read via externalRef
- id: foundationData
  template:
    apiVersion: kro.run/v1alpha1
    kind: externalRef
    spec:
      apiVersion: v1
      kind: ConfigMap
      name: foundation-bridge
      namespace: ${schema.spec.namespace}
```

## Versioned Naming Convention

| Element | Pattern | Example |
|---------|---------|---------|
| `metadata.name` | lowercase, no hyphens | `awsgen3foundation1` |
| `kind` | CamelCase | `AwsGen3Foundation1` |
| filename | `<lowercase>-rg.yaml` | `awsgen3foundation1-rg.yaml` |

Never rename an existing RGD — create a versioned successor (v2, v3) instead.

## Instance Conventions

```yaml
apiVersion: kro.run/v1alpha1
kind: AwsGen3Foundation1
metadata:
  name: gen3
  namespace: spoke1
  annotations:
    argocd.argoproj.io/sync-wave: "30"
    argocd.argoproj.io/sync-options: ServerSideApply=true
spec:
  namespace: spoke1   # only non-default field needed
```

Schema must declare `name` with default and `namespace` as required.

## AWS Account ID Injection

The account ID is never stored in git. It flows:
1. `aws sts get-caller-identity` → ArgoCD cluster Secret `aws_account_id` annotation
2. ApplicationSet cluster generator → template variable
3. Instances Helm chart → `helm.parameters` value (`awsAccountId`)
4. Spoke namespace annotation → `services.k8s.aws/owner-account-id`

RGDs read it via:
```yaml
${spokeNamespace.metadata.annotations['services.k8s.aws/owner-account-id']}
```
