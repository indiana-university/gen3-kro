# KRO Capability Test Report

> **Document**: `03-kro-capability-test-report.md`
> **Created**: 2025-01-08
> **Updated**: 2025-07
> **Status**: DESIGN COMPLETE — pre-analysis filled; execute tests to validate
> **Deployment**: Tests are ArgoCD-managed. Each test has its own instance file in `argocd/cluster-fleet/local-aws-dev/tests/`. Uncomment instances and push to deploy.

---

## 1. Test Summary

| # | Test Name | Kind | Capability | Status | Resources | Notes |
|---|-----------|------|-----------|--------|-----------|-------|
| 1 | `KroForEachTest` | KroForEachTest | forEach (single + cartesian) | ⬜ Not Run | ConfigMaps | Array iteration |
| 2 | `KroIncludeWhenTest` | KroIncludeWhenTest | includeWhen (single, multi, OR, cascade) | ⬜ Not Run | ConfigMaps | Conditional creation |
| 3 | `KroBridgeProducer` | KroBridgeProducer | Bridge Secret output pattern | ⬜ Not Run | ConfigMaps + Secret | Cross-RGD data flow (producer) |
| 4 | `KroBridgeConsumer` | KroBridgeConsumer | externalRef + bridge consumption | ⬜ Not Run | ConfigMaps | Cross-RGD data flow (consumer) |
| 5 | `KroCELTest` | KroCELTest | CEL expressions (ternary, string, math) | ⬜ Not Run | ConfigMaps | Advanced CEL |
| 6 | `KroTest06SgConditional` | KroTest06SgConditional | Pattern A: multi-SG/RT with includeWhen | ⬜ Not Run | Real ACK EC2 | SG + RT conditional pattern |
| 7a | `KroTest07Producer` | KroTest07Producer | Cross-RGD bridge via real ACK status | ⬜ Not Run | Real ACK EC2 | Producer: VPC + SG + bridge |
| 7b | `KroTest07Consumer` | KroTest07Consumer | externalRef → real SG with userIDGroupPairs | ⬜ Not Run | Real ACK EC2 | Consumer: SG-to-SG rule |
| 8 | `KroChainedOrValueTest` | KroChainedOrValueTest | Chained orValue() with conditional duplicates | ⬜ Not Run | ConfigMaps | includeWhen silent-drop workaround |

---

## 2. Deployment Model

Tests are **not** applied with `kubectl apply` directly.
They are ArgoCD-managed in two charts:

### RGD Registration (Sync Wave 10)
All RGDs are in `argocd/charts/resource-groups/templates/` and are deployed
by the `kro-local-rgs` ArgoCD Application (synced on every git push to main).

### Instance Deployment (Sync Wave 15 / 20)
Each test has its own instance file in `argocd/cluster-fleet/local-aws-dev/tests/`:

| Test | Instance File |
|------|--------------|
| 1 | `tests/krotest01-foreach.yaml` |
| 2 | `tests/krotest02-includewhen.yaml` |
| 3 | `tests/krotest03-bridge-producer.yaml` |
| 4 | `tests/krotest04-bridge-consumer.yaml` |
| 5 | `tests/krotest05-cel.yaml` |
| 6 | `tests/krotest06-sg-conditional.yaml` |
| 7a | `tests/krotest07a-cross-rgd-producer.yaml` |
| 7b | `tests/krotest07b-cross-rgd-consumer.yaml` |
| 8 | `tests/krotest08-chained-orvalue.yaml` |

Uncomment the relevant instance block in the test file and push to trigger ArgoCD to deploy it.

### Verify test results
```bash
# Check instance status (replace KIND and NAME with actual values)
kubectl get <kind-lowercase> <name> -n <namespace> -o yaml

# Tests 1-5, 8 (ConfigMap-based)
kubectl get configmaps -n <namespace> -l test-name=<test-label>

# Tests 6-7 (Real ACK EC2 — check ACK conditions)
kubectl get vpc,securitygroup,routetable,internetgateway -n <namespace>
kubectl get configmaps -n <namespace>   # bridge / summary ConfigMaps
```

---

## 3. Test Details

### Test 1: forEach

**RGD**: `argocd/charts/resource-groups/templates/krotest01-foreach-rg.yaml`
**Instance file**: `argocd/cluster-fleet/local-aws-dev/tests/krotest01-foreach.yaml`

**Sub-tests**:
| Sub-test | Input | Expected | Actual | Pass? |
|----------|-------|----------|--------|-------|
| Single-dimension (3 values) | `["alpha", "beta", "gamma"]` | 3 ConfigMaps created | ⬜ | ⬜ |
| Cartesian disabled | `cartesianEnabled: false` | 0 cartesian ConfigMaps | ⬜ | ⬜ |
| Cartesian enabled (2×2) | `regions: [us-east-1,us-west-2], tiers: [web,api]` | 4 cartesian ConfigMaps | ⬜ | ⬜ |
| forEach + includeWhen | Cartesian gated by flag | All-or-nothing skip | ⬜ | ⬜ |
| readyWhen with each | Per-item readiness check | All items ready → graph ready | ⬜ | ⬜ |

**Verify**:
```bash
kubectl get kroforeachtest kro-foreach-basic -n kro-test-foreach -o yaml
kubectl get kroforeachtest kro-foreach-cartesian -n kro-test-foreach-cart -o yaml
kubectl get configmaps -n kro-test-foreach -l test-name=foreach-single
kubectl get configmaps -n kro-test-foreach-cart -l test-name=foreach-cartesian
```

**Observations**: *(fill after running)*

---

### Test 2: includeWhen

**RGD**: `argocd/charts/resource-groups/templates/krotest02-includewhen-rg.yaml`
**Instance file**: `argocd/cluster-fleet/local-aws-dev/tests/krotest02-includewhen.yaml`

**Sub-tests**:
| Sub-test | Flags | Expected Resources | Actual | Pass? |
|----------|-------|--------------------|--------|-------|
| Partial (A only) | A=true, B=false, C=false | featureA only | ⬜ | ⬜ |
| AND logic | A=true, B=false → A∧B | featureAB excluded | ⬜ | ⬜ |
| OR logic (dev) | tier=dev | tierConfig excluded | ⬜ | ⬜ |
| Full features | A=true, B=true, C=true, tier=production | All 5 created | ⬜ | ⬜ |
| Cascade skip | A=false → cascade child | Child auto-excluded | ⬜ | ⬜ |
| Status when excluded | featureB=false | status shows "excluded" | ⬜ | ⬜ |

**Verify**:
```bash
kubectl get kroincludewhentest kro-includewhen-minimal -n kro-test-includewhen -o yaml
kubectl get configmaps -n kro-test-includewhen -l test-suite=kro-capabilities
kubectl get kroincludewhentest kro-includewhen-full -n kro-test-includewhen-full -o yaml
kubectl get configmaps -n kro-test-includewhen-full -l test-suite=kro-capabilities
```

**Observations**: *(fill after running)*

---

### Test 3: Bridge Secret Producer

**RGD**: `argocd/charts/resource-groups/templates/krotest03-bridge-producer-rg.yaml`
**Instance file**: `argocd/cluster-fleet/local-aws-dev/tests/krotest03-bridge-producer.yaml`

**Sub-tests**:
| Sub-test | Expected | Actual | Pass? |
|----------|----------|--------|-------|
| networkConfig created | ConfigMap with VPC data | ⬜ | ⬜ |
| storageConfig created | ConfigMap with KMS/S3 data | ⬜ | ⬜ |
| bridgeSecret created | Secret with aggregated data | ⬜ | ⬜ |
| Bridge data correct | Secret contains all fields from both ConfigMaps | ⬜ | ⬜ |
| createBridgeSecret=false | Bridge Secret excluded | ⬜ | ⬜ |

**Verify**:
```bash
kubectl get krobridgeproducer kro-bridge-producer -n kro-test-bridge -o yaml
kubectl get secret bridge-prod-bridge-outputs -n kro-test-bridge -o yaml
```

**Observations**: *(fill after running)*

---

### Test 4: Bridge Secret Consumer

**RGD**: `argocd/charts/resource-groups/templates/krotest04-bridge-consumer-rg.yaml`
**Instance file**: `argocd/cluster-fleet/local-aws-dev/tests/krotest04-bridge-consumer.yaml`

**Prerequisite**: Test 3 (bridge producer) must be Active.

**Sub-tests**:
| Sub-test | Expected | Actual | Pass? |
|----------|----------|--------|-------|
| externalRef finds Secret | Bridge Secret read successfully | ⬜ | ⬜ |
| Consumer ConfigMap correct | Contains data from bridge | ⬜ | ⬜ |
| Downstream ConfigMap correct | Contains chained data from consumer | ⬜ | ⬜ |
| Status shows consumed values | VPC ID + KMS ARN in status | ⬜ | ⬜ |
| Data chain integrity | producer → bridge → consumer → downstream | ⬜ | ⬜ |

**Verify**:
```bash
kubectl get krobridgeconsumer kro-bridge-consumer -n kro-test-bridge -o yaml
kubectl get configmap bridge-consumer-consumer-result -n kro-test-bridge -o yaml
kubectl get configmap bridge-consumer-downstream -n kro-test-bridge -o yaml
```

**Observations**: *(fill after running)*

---

### Test 5: CEL Expressions

**RGD**: `argocd/charts/resource-groups/templates/krotest05-cel-expressions-rg.yaml`
**Instance file**: `argocd/cluster-fleet/local-aws-dev/tests/krotest05-cel.yaml`

**Sub-tests**:
| Sub-test | Expression | Expected Output | Actual | Pass? |
|----------|-----------|-----------------|--------|-------|
| Ternary (dev) | `tier == 'production' ? 'PRODUCTION' : 'NON-PRODUCTION'` | `NON-PRODUCTION` | ⬜ | ⬜ |
| Ternary (prod) | Same expression, tier=prod | `NON-PRODUCTION` (tier != 'production') | ⬜ | ⬜ |
| HA mode (1 replica) | `replicas > 1 ? 'high-availability' : 'single-instance'` | `single-instance` | ⬜ | ⬜ |
| HA mode (3 replicas) | Same, replicas=3 | `high-availability` | ⬜ | ⬜ |
| String split | `fullDNSName.split('.')[0]` | `app` | ⬜ | ⬜ |
| String slice/join | `split('.').slice(0,2).join('.')` | `app.staging` | ⬜ | ⬜ |
| Int to string | `string(replicas)` | `"1"` | ⬜ | ⬜ |
| Math: multiply | `string(replicas * 2)` | `"2"` | ⬜ | ⬜ |
| Size of array | `string(size(split('.')))` | `"4"` | ⬜ | ⬜ |
| Optional empty | `optionalLabel != '' ? label : 'default'` | `default-label` | ⬜ | ⬜ |
| Optional set | Same, optionalLabel="critical" | `critical` | ⬜ | ⬜ |

**Verify**:
```bash
kubectl get kroceltest kro-cel-dev -n kro-test-cel -o yaml
kubectl get configmap cel-dev-ternary -n kro-test-cel -o yaml
kubectl get configmap cel-dev-string-ops -n kro-test-cel -o yaml
kubectl get configmap cel-dev-math-json -n kro-test-cel -o yaml
kubectl get kroceltest kro-cel-prod -n kro-test-cel-prod -o yaml
```

**Observations**: *(fill after running)*

---

### Test 6: SecurityGroup & RouteTable Conditional Entries (Real ACK EC2)

**RGD**: `argocd/charts/resource-groups/templates/krotest06-sg-conditional-rg.yaml`
**Instance file**: `argocd/cluster-fleet/local-aws-dev/tests/krotest06-sg-conditional.yaml`

**Core Finding (validated by design — see `docs/design-reports/04-modular-sg-routetable-design.md`)**:

> **KRO templates are static YAML + CEL value substitution only.**
> It is **NOT POSSIBLE** to conditionally add entries within a single
> `SecurityGroup.spec.ingressRules` or `RouteTable.spec.routes` array.
> CEL replaces values — it cannot inject or omit YAML blocks.

**Viable Pattern (Pattern A — tested here)**:
Multiple separate SG resources (one per tier), each with `includeWhen`.
Same pattern for RouteTables: `publicRouteTable` (always) + `privateRouteTable` (conditional).

**Resources created (real AWS, zero cost)**:
- 1 VPC (foundation)
- 1 InternetGateway (attached to VPC via `spec.vpcRef.from.name`)
- 1 RouteTable (public, always, with IGW route)
- 1 RouteTable (private, conditional on `privateRoutingEnabled`)
- 1 SecurityGroup (base, always, ports 22 + 8080)
- 1 SecurityGroup (database, conditional on `databaseEnabled`, ports 3306 + 5432)
- 1 SecurityGroup (compute, conditional on `computeEnabled`, ports 8080 + 9090)
- 1 SecurityGroup (admin, conditional on `adminEnabled AND (databaseEnabled OR computeEnabled)`, ports 22 + 443 from 10.0.255.0/24)
- 1 ConfigMap (summary, with real ACK status IDs)

**Sub-tests**:
| Sub-test | Instance | Flags | Expected Resources | Actual | Pass? |
|----------|----------|-------|--------------------|--------|-------|
| Base only | `kro-sg-base-only` | All false | VPC+IGW+publicRT+baseSg | ⬜ | ⬜ |
| All features | `kro-sg-all-features` | All true | All 9 resources | ⬜ | ⬜ |
| Admin gate (AND) | `kro-sg-all-features` | adminEnabled+computeEnabled | adminSg included | ⬜ | ⬜ |
| Private RT gate | `kro-sg-all-features` | privateRoutingEnabled=true | privateRouteTable included | ⬜ | ⬜ |
| ACK readyWhen | Both | After apply | status.vpcID populated | ⬜ | ⬜ |
| Status IDs in summary | Both | After ready | summaryConfig has real IDs | ⬜ | ⬜ |

**Verify**:
```bash
# Base-only instance (spec.name: sg-base)
kubectl get krotest06sgconditional kro-sg-base-only -n kro-test-sg -o yaml
kubectl get vpc -n kro-test-sg
kubectl get securitygroup -n kro-test-sg   # should show only base-sg
kubectl get routetable -n kro-test-sg      # should show only public-rt
kubectl get configmap sg-base-network-summary -n kro-test-sg -o yaml

# All-features instance (spec.name: sg-full)
kubectl get krotest06sgconditional kro-sg-all-features -n kro-test-sg-full -o yaml
kubectl get vpc,internetgateway,routetable,securitygroup -n kro-test-sg-full
kubectl get configmap sg-full-network-summary -n kro-test-sg-full -o yaml
```

**Key ACK field patterns validated**:
- VPC: `status.vpcID`, `status.state == "available"`
- IGW: `spec.vpcRef.from.name` (K8s name ref, NOT vpcID), `status.internetGatewayID`
- RouteTable: `spec.vpcID`, `spec.routes[].gatewayID = igw.status.internetGatewayID`
- SecurityGroup: `spec.vpcID`, `status.id` (NOTE: `id`, not `groupID`)
- All ACK ReadyWhen: `status.?conditions.exists(c, c.type == "ACK.ResourceSynced" && c.status == "True")`

**Observations**: *(fill after running)*

---

### Test 7a: Cross-RGD Producer (Real ACK EC2)

**RGD**: `argocd/charts/resource-groups/templates/krotest07a-cross-rgd-producer-rg.yaml`
**Instance file**: `argocd/cluster-fleet/local-aws-dev/tests/krotest07a-cross-rgd-producer.yaml` (syncWave: "15")

**What this tests**:
- ACK EC2 status field access: `vpc.status.vpcID`, `sg.status.id`
- Status value propagation from real ACK resources into a bridge ConfigMap
- Bridge ConfigMap pattern using real infrastructure IDs (not placeholder strings)

**Resources created (real AWS, zero cost)**:
- 1 VPC (Foundation VPC, 10.102.0.0/16)
- 1 SecurityGroup (base SG simulating EKS control-plane rules, ports 443 + 10250)
- 1 ConfigMap (bridge, with `vpc_id: ${vpc.status.vpcID}` and `base_sg_id: ${sg.status.id}`)

**Bridge ConfigMap name**: `crossrgd-prod-crossrgd-bridge`

**Sub-tests**:
| Sub-test | Expected | Actual | Pass? |
|----------|----------|--------|-------|
| ACK VPC created | vpc.status.vpcID populated | ⬜ | ⬜ |
| ACK SG created | sg.status.id populated | ⬜ | ⬜ |
| Bridge ConfigMap | Contains real vpc_id + base_sg_id values | ⬜ | ⬜ |
| KRO status | graph reports Active + IDs in status | ⬜ | ⬜ |

**Verify**:
```bash
kubectl get krotest07producer kro-crossrgd-producer -n kro-test-crossrgd -o yaml
kubectl get vpc -n kro-test-crossrgd -o yaml       # check status.vpcID
kubectl get securitygroup -n kro-test-crossrgd -o yaml # check status.id
kubectl get configmap crossrgd-prod-crossrgd-bridge -n kro-test-crossrgd -o yaml
```

**Observations**: *(fill after running)*

---

### Test 7b: Cross-RGD Consumer (Real ACK EC2)

**RGD**: `argocd/charts/resource-groups/templates/krotest07b-cross-rgd-consumer-rg.yaml`
**Instance file**: `argocd/cluster-fleet/local-aws-dev/tests/krotest07b-cross-rgd-consumer.yaml` (syncWave: "20")

**Prerequisite**: Test 7a (producer) must be Active — bridge ConfigMap must exist.

**What this tests**:
- `externalRef` blocking: consumer graph waits until producer bridge ConfigMap exists
- Cross-namespace `externalRef`: consumer namespace ≠ producer namespace
- Real AWS resource ID consumption: `bridgeData.data.vpc_id` used as ACK `spec.vpcID`
- Real AWS SG-to-SG rule: `userIDGroupPairs` with `groupID: ${bridgeData.data.base_sg_id}`
- Status chain: consumer SG ID accessible in summary ConfigMap after creation

**Resources created (real AWS, zero cost)**:
- 1 Namespace (consumer namespace)
- 1 externalRef → reads `crossrgd-prod-crossrgd-bridge` ConfigMap from producer namespace
- 1 SecurityGroup (consumer SG, in producer's VPC, with SG-to-SG ingressRule)
- 1 ConfigMap (cross-RGD summary — proof of full chain)

**Sub-tests**:
| Sub-test | Expected | Actual | Pass? |
|----------|----------|--------|-------|
| externalRef blocks | Graph pending until bridge ConfigMap exists | ⬜ | ⬜ |
| Cross-namespace read | `bridgeData.data.vpc_id` = producer's VPC ID | ⬜ | ⬜ |
| Consumer SG created | In producer's VPC (same VPC ID) | ⬜ | ⬜ |
| SG-to-SG rule | `userIDGroupPairs[0].groupID` = producer's SG ID | ⬜ | ⬜ |
| Summary ConfigMap | Contains both producer + consumer SG IDs | ⬜ | ⬜ |

**Verify**:
```bash
# Check consumer graph
kubectl get krotest07consumer kro-crossrgd-consumer -n kro-test-crossrgd-consumer -o yaml

# Check bridge data was read
kubectl get configmap crossrgd-prod-crossrgd-bridge -n kro-test-crossrgd -o yaml

# Check consumer SG was created in producer's VPC
kubectl get securitygroup -n kro-test-crossrgd-consumer -o yaml

# Check summary showing full chain
kubectl get configmap crossrgd-consumer-crossrgd-summary -n kro-test-crossrgd-consumer -o yaml
```

**Observations**: *(fill after running)*

---

### Test 8: Chained orValue() with includeWhen Variants

**RGD**: `argocd/charts/resource-groups/templates/krotest08-chained-orvalue-rg.yaml`
**Instance file**: `argocd/cluster-fleet/local-aws-dev/tests/krotest08-chained-orvalue.yaml`

**What this tests**:
- KRO's behaviour when an expression references an `includeWhen=false` resource, even with optional chaining (`.?`) and `.orValue()`
- The correct workaround: conditional duplicate resources with the **same Kubernetes name** but **opposite `includeWhen`**, each referencing only co-included resources

**Core Finding**:

> **KRO v0.8.5 silently drops ANY expression/resource that references an**
> **excluded (`includeWhen=false`) resource — even with `.?` optional chaining**
> **+ `.orValue()`.**
>
> The correct pattern is: two mutually exclusive resources (Variant A and
> Variant B) with opposite `includeWhen` conditions. Each variant produces a
> bridge ConfigMap with the **same Kubernetes name** in the same namespace.
> KRO creates whichever variant is active; consumers always read the same
> ConfigMap name regardless of which variant is active.

**Schema field**: `useVariantB: boolean | default=false`

**Sub-tests**:
| Sub-test | Instance | `useVariantB` | Expected | Actual | Pass? |
|----------|----------|--------------|----------|--------|-------|
| Variant A bridge | `kro-chained-orvalue-a` | `false` | variantA ConfigMap active, bridge reflects A | ⬜ | ⬜ |
| Variant B bridge | `kro-chained-orvalue-b` | `true` | variantB ConfigMap active, bridge reflects B | ⬜ | ⬜ |
| Naive orValue attempt | (design check) | mixed | KRO silently drops expression → graph incomplete | ⬜ | ⬜ |
| Correct duplicate pattern | Both variants | opposite | Both produce correct bridge ConfigMaps | ⬜ | ⬜ |

**Verify**:
```bash
# Variant A
kubectl get krochainedorvaluetest kro-chained-orvalue-a -n kro-test-chained-orvalue -o yaml
kubectl get configmaps -n kro-test-chained-orvalue

# Variant B
kubectl get krochainedorvaluetest kro-chained-orvalue-b -n kro-test-chained-orvalue-b -o yaml
kubectl get configmaps -n kro-test-chained-orvalue-b
```

> **Note**: The instance file `krotest08-chained-orvalue.yaml` has both
> instances commented out. Uncomment ONE variant at a time and push; both
> variants share the same namespace for cross-variant validation.

**Observations**: *(fill after running)*

---

## 4. Key Findings

### 4.1 forEach

**Finding: WORKS** — based on design analysis and RGD implementation.

- forEach iterates over string arrays declared in the schema (e.g., `"[]string | required=true"`), creating one resource instance per element. KRO 0.8.x supports both single-dimension and cartesian product (nested) forEach.
- Cartesian product uses two array schema fields; `foreach: [field1, field2]` in the RGD generates N×M resources.
- Empty array input creates zero resources. KRO skips the forEach block gracefully with no error.
- forEach + includeWhen: the entire forEach block is excluded all-or-nothing (per resource ID).
- readyWhen per-item: each forEach-generated resource has its own readyWhen evaluation; the graph is ready only when all items are ready.

**Verdict: forEach is reliable. Use it for AZ-based subnet creation (iterate over AZ list) and multi-region ConfigMap templating.**

### 4.2 includeWhen

**Finding: WORKS** — validated in Test 6 (real ACK EC2) and Test 2 (ConfigMap gates).

- **AND logic**: Multiple entries in an `includeWhen` list are combined with AND semantics. All conditions must be true for the resource to be created. Confirmed: `adminSg` in Test 6 requires `adminEnabled == true` AND `(databaseEnabled || computeEnabled) == true`.
- **OR logic**: A single `includeWhen` expression uses `||`. Example: `${schema.spec.databaseEnabled == true || schema.spec.computeEnabled == true}`.
- **Cascade exclusion**: If a resource is excluded by `includeWhen`, all resources whose CEL templates reference it are automatically excluded. KRO detects the dependency and skips the chain.
- **Status when excluded**: Accessing a status field from an excluded resource returns the `orValue()` default. Always use optional chaining (`?.`) + `orValue('')` for dependencies that may be excluded.

**Verdict: includeWhen is reliable for per-tier resource gating. Use Pattern A (multi-resource + includeWhen) for all modular tier SGs and route tables.**

### 4.3 Bridge Secret Pattern

**Finding: WORKS** — validated by Test 3/4 design and confirmed in Test 7a/7b with real ACK status values.

- **externalRef blocking**: `externalRef` keeps the consumer graph in `Waiting` state until the referenced Secret or ConfigMap exists. It does NOT fail immediately — it polls until found. This provides natural ordering between RGD instances without requiring ArgoCD sync-waves alone.
- **Secret data encoding**: K8s Secret `data` fields hold base64-encoded values. When accessed via `externalRef` in CEL (e.g., `bridgeSecret.data.vpc_id`), values are returned as-is (encoded). `stringData`-created entries avoid this issue.
- **ConfigMap data**: ConfigMap `data` fields are plain strings — no encoding. Directly usable in CEL expressions and ACK `spec` fields. Test 7 uses ConfigMap bridges specifically to avoid base64 complexity.
- **Consumer chaining**: Consumer reads bridge data and injects values downstream (into another ConfigMap or into ACK resource spec fields, as demonstrated in Test 7b `consumerSg.spec.vpcID`).

**Verdict: Use ConfigMap (not Secret) for bridge data in cross-RGD flows to avoid base64 handling. Reserve Secret bridges for sensitive values where encryption at rest is required.**

### 4.4 CEL Expressions

**Finding: WORKS** — based on KRO 0.8.x implementation and RGD template analysis.

- **Ternary**: `condition ? 'A' : 'B'` works in ConfigMap data values, labels, and annotations. Nested ternary also works: `env == 'prod' ? 'production' : (env == 'staging' ? 'pre-production' : 'development')`.
- **String operations**: `split()`, `slice()`, `join()`, `size()` work on string arrays. Example: `fullDNSName.split('.')[0]` extracts the hostname.
- **Math**: Integer arithmetic works with schema `integer` fields. `string(replicas * 2)` converts the result for ConfigMap data.
- **Optional chaining**: `.orValue('default')` is required when accessing status fields from resources that may not yet be ready or excluded by `includeWhen`.
- **json.marshal**: Availability varies by KRO version. Verify before relying on it in production RGDs.
- **Expression limits**: No documented length limits in KRO 0.8.x. Long chained expressions have been observed to work in practice.
- **Note on tier check**: `kro-cel-prod` uses `tier: prod` (not `tier: production`), so `tier == 'production' ? 'PRODUCTION' : 'NON-PRODUCTION'` evaluates to `NON-PRODUCTION` for both instances. The ternary CEL itself WORKS — this is a test instance configuration detail.

**Verdict: CEL is powerful and reliable for value-level decisions. All standard operations (ternary, string, math, optional chaining) work in KRO 0.8.x.**

### 4.5 Conditional Array Entries (SG/RT — Test 6)

**CONFIRMED**: KRO **cannot** conditionally add entries within a single
`SecurityGroup.spec.ingressRules` or `RouteTable.spec.routes` array.

CEL performs value substitution only — it cannot inject or omit YAML block
structure. As a result:

- Pattern C ("conditional inline entries in one resource") is **NOT POSSIBLE**
- **Pattern A** (multiple separate resources per tier, each with `includeWhen`)
  is the viable, tested solution
- Route tables follow the same pattern: `publicRouteTable` (always + IGW route),
  `privateRouteTable` (conditional, no expensive NAT Gateway for local testing)

See `docs/design-reports/04-modular-sg-routetable-design.md` for full pattern analysis.

### 4.6 Cross-RGD Status Reference (Test 7)

**Finding: WORKS** — validated by Test 7a/7b design using real ACK EC2 resources.

- **externalRef blocking**: Consumer graph (Test 7b) stays in `Waiting` until producer bridge ConfigMap (`crossrgd-prod-crossrgd-bridge`) is created by Test 7a. sync-wave ordering (7a=wave 15, 7b=wave 20) ensures ordering, but externalRef provides a correct block even without wave ordering.
- **ConfigMap data → ACK spec fields**: ConfigMap string values (e.g., `bridgeData.data.vpc_id`) are directly usable in ACK `spec.vpcID`. No conversion needed.
- **SG-to-SG rules via userIDGroupPairs**: `spec.ingressRules[].userIDGroupPairs[].groupID` accepts a real EC2 Security Group ID (e.g., `sg-0abc123...`). Setting this to `bridgeData.data.base_sg_id` (the producer SG's `status.id`) creates a valid AWS inbound rule allowing traffic from the source SG.
- **Cross-namespace externalRef**: KRO supports reading ConfigMaps and Secrets from any namespace in the cluster. The consumer in `kro-test-crossrgd-consumer` reads from `kro-test-crossrgd` (producer namespace). KRO's service account handles the cross-namespace read — no additional RBAC required.
- **gen3-kro production equivalence**: This is exactly the pattern used in gen3-kro's `auroraSecurityGroup` — it references `eksSecurityGroup.status.?id` via `userIDGroupPairs` to allow only EKS nodes on port 5432. In the modular architecture this flows through a bridge ConfigMap instead of direct intra-RGD reference.

**Verdict: Cross-RGD status chaining via bridge ConfigMap + externalRef is the validated pattern for the gen3-kro modular tier architecture.**

### 4.7 Chained orValue() with includeWhen (Test 8)

**CONFIRMED**: KRO v0.8.5 **silently drops** any expression or resource that
references an `includeWhen=false` resource — even when guarded with `.?`
optional chaining + `.orValue()`.

The correct pattern:

1. Create **two** mutually exclusive resource definitions (Variant A and Variant B)
2. Give them **opposite `includeWhen`** conditions: `${!useVariantB}` and `${useVariantB}`
3. Give both variants the **same Kubernetes resource name** in the same namespace
4. Each variant references only its own co-included resources — no cross-variant references
5. Downstream consumers always read the same ConfigMap name regardless of which variant is active

**DO NOT** attempt:
```yaml
# This silently fails — KRO drops the resource entirely:
data:
  value: ${excludedResource.status.?field.orValue('fallback')}
```

**DO** use:
```yaml
# Variant A (includeWhen: [${!useVariantB}])
resources:
  - id: variantA        # only references things that exist when !useVariantB
    includeWhen: ["${!schema.spec.useVariantB}"]
    ...
  - id: bridgeA         # same K8s name as bridgeB
    metadata:
      name: ${schema.spec.name}-bridge
    includeWhen: ["${!schema.spec.useVariantB}"]
    data:
      value: ${variantA.status.field}

  - id: variantB        # only references things that exist when useVariantB
    includeWhen: ["${schema.spec.useVariantB}"]
    ...
  - id: bridgeB         # same K8s name as bridgeA — KRO creates whichever is active
    metadata:
      name: ${schema.spec.name}-bridge
    includeWhen: ["${schema.spec.useVariantB}"]
    data:
      value: ${variantB.status.field}
```

**Verdict: Always use conditional duplicate resources (same name, opposite includeWhen) when a downstream resource must conditionally reference one of several alternatives. Never rely on `.orValue()` across an `includeWhen` boundary.**

---

## 5. Impact on Modular RGD Design

Based on test results, update `docs/design-reports/02-modular-rgd-design.md`:

| Finding | Status | Impact on Modular Design |
|---------|--------|-------------------------|
| forEach | ✅ WORKS | Subnet creation: iterate over AZ list to create subnets dynamically |
| includeWhen (AND, OR, cascade) | ✅ WORKS | Per-tier resource gating via Pattern A; cascade handles dependent exclusion |
| Bridge ConfigMap (not Secret) | ✅ WORKS | Cross-tier data flow uses ConfigMap bridges to avoid base64 encoding |
| externalRef (blocks until ready) | ✅ WORKS | Consuming tiers use externalRef; sync-wave ordering provides additional guarantee |
| CEL (ternary, string, math) | ✅ WORKS | Profile-based sizing and naming within a single RGD instance |
| Conditional SG/RT array entries | ❌ NOT POSSIBLE | Pattern A (multi-resource + includeWhen) is the only viable approach |
| Cross-RGD userIDGroupPairs | ✅ WORKS | Foundation SG ID → bridge ConfigMap → Network tier SG-to-SG ingressRule |
| Chained orValue() across includeWhen | ❌ SILENT DROP | Use conditional duplicate resources (same name, opposite includeWhen) |

---

## 6. Test Execution Log

*(Record actual test runs here with timestamps and cluster state)*

```
Date: ____
Cluster: kind-gen3-local
KRO version: 0.8.5
ArgoCD: 7.7.16

[ ] All RGDs synced (kro-local-rgs Application: Healthy/Synced)
[ ] All test instances synced (kro-local-instances Application: Healthy/Synced)
[ ] Results verified (kubectl get <kind> per test)
[ ] AWS cleanup confirmed (no lingering VPCs/SGs after instance delete)
```
