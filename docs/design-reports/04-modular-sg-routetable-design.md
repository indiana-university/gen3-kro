# Plan 04: Modular SecurityGroup & RouteTable Design for KRO

> **Status:** Architecture design document  
> **Relates to:** Test 6 findings (krotest06-sg-conditional-rg.yaml)  
> **Context:** gen3-dev KRO capability testing → gen3-kro modular RGD architecture

---

## The Problem

The modular RGD architecture (Plan 02) splits gen3 infrastructure into tiers:
Foundation → Network → Database → Compute → Search → AppIAM → Monitoring.  
Each tier is an independent RGD instance that can be deployed, upgraded, or
removed without touching adjacent tiers.

**Desired behaviour (NOT achievable in KRO):**
> One SecurityGroup resource whose `spec.ingressRules` list grows as each
> optional tier is enabled. e.g. enabling the Database tier adds MySQL/Postgres
> rules to a shared SG; enabling Compute adds API/gRPC rules.

**Why it cannot work in KRO:**  
KRO templates are static YAML parsed before any CEL expression evaluation.
`spec.ingressRules` is an array; its entries must be literal YAML. There is
no Helm-style `{{- if }}` or Jinja block templating inside KRO templates.
CEL substitutes *values* only — it cannot add or remove array *elements*.

Attempting conditional array entries results in invalid YAML that KRO rejects
at validation time.

---

## Three Viable Patterns

### Pattern A — Multi-SG with includeWhen (RECOMMENDED)

**How it works:** Each tier creates its own SecurityGroup resource guarded by
`includeWhen`. Workloads (EC2 instances, EKS node groups) attach multiple SGs.
The ACK EC2 and EKS controllers accept a list of SG IDs, so this is natural.

```
Foundation tier  →  base-sg  (always)  port 22/tcp, 80/tcp, 8080/tcp (health)
Database tier    →  db-sg    (optional) port 3306/tcp, 5432/tcp (from private subnet)
Compute tier     →  compute-sg (optional) port 8080/tcp, 9090/tcp (from internal)
Admin SG         →  admin-sg (AND: adminEnabled AND (db OR compute))
```

**KRO implementation:**
```yaml
resources:
  - id: baseSg
    template:                         # always present
      kind: SecurityGroup
      spec:
        ingressRules:
          - {fromPort: 22, toPort: 22, ipProtocol: tcp, ...}

  - id: databaseSg
    includeWhen:
      - ${schema.spec.databaseEnabled == true}
    template:                         # optional — only when databaseEnabled
      kind: SecurityGroup
      spec:
        ingressRules:
          - {fromPort: 3306, toPort: 3306, ipProtocol: tcp, ...}
          - {fromPort: 5432, toPort: 5432, ipProtocol: tcp, ...}

  - id: adminSg
    includeWhen:
      - ${schema.spec.adminEnabled == true}
      - ${schema.spec.databaseEnabled == true || schema.spec.computeEnabled == true}
```

**Instance attachment (ACK EKS or EC2 example):**
```yaml
spec:
  securityGroupIDs:
    - ${baseSg.status.id}
    - ${databaseSg.status.?id.orValue('')}   # empty string if excluded
    - ${computeSg.status.?id.orValue('')}
```

**Pros:**
- Clean per-tier separation: each SG is owned and controlled by one tier
- KRO includeWhen is well-tested and reliable
- SGs can have different deletion policies per tier
- No cross-tier coordination needed at the SG level

**Cons:**
- EC2/EKS resources must build their SG list dynamically (use optional chaining)
- AWS allows max 5 SGs per ENI by default (raise limit if needed)
- More SG resources to manage in AWS console

**Verdict: Preferred pattern for gen3-kro modular RGDs.**

---

### Pattern B — Schema-Driven Full Rule Injection

**How it works:** The instance provides the *complete* ingress/egress rule list
as a schema field (`[]object`). The RGD template injects it wholesale. The RGD
itself contains no conditional logic for rules — all decisions live in instance
values.

```yaml
# Schema
spec:
  ingressRules: "[]object | default=[]"

# RGD template
spec:
  ingress: ${schema.spec.ingressRules}
```

**Instance example:**
```yaml
spec:
  ingressRules:
    - fromPort: 22
      toPort: 22
      ipProtocol: tcp
      ipRanges:
        - cidrIP: "0.0.0.0/0"
    - fromPort: 3306   # add only if database tier enabled
      toPort: 3306
      ipProtocol: tcp
      ipRanges:
        - cidrIP: "10.0.0.0/16"
```

**Pros:**
- Single SG per workload — simpler than multi-SG
- Full flexibility: any combination of rules, any structure
- Rules are version-controlled in the instance YAML (infrastructure/<tier>.yaml)

**Cons:**
- Pushes all logic to instance values → templates are less self-documenting
- Operators must know the full ACK rule schema when writing instances
- No per-tier isolation: a Database rules change requires editing the Compute
  tier's instance values
- `[]object` schema support in KRO may be limited (test before relying on it)

**Verdict: Use when a single SG per workload is an architectural requirement.
Avoid for modular tier usage — violates tier separation.**

---

### Pattern C — Conditional Inline Array Entries (NOT POSSIBLE)

This pattern is included for documentation only. It describes what developers
*expect* to work but cannot.

```yaml
# INVALID — KRO does NOT support block-level conditionals
spec:
  ingressRules:
    - fromPort: 22          # always present
      toPort: 22
      ipProtocol: tcp
    # {{- if schema.spec.databaseEnabled }}   # SYNTAX ERROR in KRO context
    - fromPort: 3306
      toPort: 3306
      ipProtocol: tcp
    # {{- end }}
```

KRO uses CEL for value substitution, not Go templating or Jinja. There is no
mechanism to conditionally include array elements within a resource template.

**Verdict: Not possible in KRO 0.8.x. File a feature request with the KRO
project if this pattern is needed.**

---

### Pattern D — Static "Kitchen-Sink" SG

**How it works:** One SG with ALL possible rules across all tiers, always
created. Tiers that don't need a rule don't call it; security is handled at
the network layer (subnet routing, NACLs) rather than SG granularity.

**Pros:** Simple — one SG, one RGD resource, no conditional logic  
**Cons:** Violates least-privilege; SG rules aren't auditable per tier; harder
to rotate rules when a tier is removed

**Verdict: Acceptable only for dev/test. Not appropriate for production gen3.**

---

## Route Table Analysis

The same conditional-entry limitation applies to AWS Route Tables. ACK manages
routes inline in `spec.routes`. You cannot conditionally add a NAT gateway
route based on `natEnabled`.

**Viable approaches for gen3-kro:**

### Option 1 — Separate Route Table Resources per Tier
Each tier that requires routing changes creates its own Route Table resource
(or a RouteTable update resource). Subnets are associated accordingly.

```
Foundation:  public-rt  (IGW route — always present)
Network:     private-rt (NAT gateway route — when natEnabled)
Database:    db-rt      (local VPC only — when dbEnabled)
```

This requires subnets to be re-associated when tiers change. ACK EC2 supports
`SubnetRouteTableAssociation` as a separate resource.

### Option 2 — Pre-built Route Tables with NAT Optional
The Foundation tier creates BOTH a basic private-rt (no NAT) and a nat-rt
(with NAT gateway route). The Network tier's `routeTableId` field points to
whichever is appropriate based on `natEnabled`.

```yaml
- id: basicPrivateRt     # no NAT — for dev/cost-savings
  includeWhen:
    - ${schema.spec.natEnabled == false}

- id: natPrivateRt       # with NAT — for production
  includeWhen:
    - ${schema.spec.natEnabled == true}
```

Only one private-rt is created; subnets reference `${basicPrivateRt.status.?routeTableID.orValue('')}` or `${natPrivateRt...}`.

**Verdict: Option 2 is preferred — no subnet re-association needed, clear
per-environment intent.**

---

## Recommended Architecture for gen3-kro Modular Tiers

Based on the capability test findings, here is the recommended SG and route
table strategy for the 7-tier modular RGD architecture:

| Tier | SGs Created | Route Table |
|------|-------------|-------------|
| Foundation | `{name}-base-sg` (always) | public-rt (IGW), basic-private-rt |
| Network | `{name}-nat-rt` (when natEnabled), re-associates private subnets | NAT private-rt (replaces basic) |
| Database | `{name}-db-sg` (MySQL/Postgres from private subnet) | db-rt (local only) |
| Compute | `{name}-compute-sg` (API/gRPC from internal) | — (uses private-rt) |
| AppIAM | — | — |
| Search | `{name}-search-sg` (OpenSearch from internal) | — |
| Monitoring | — | — |

Each workload resource (EKS, EC2, RDS) attaches SG list via optional chaining:

```yaml
spec:
  securityGroupIDs:
    - ${baseSg.status.id}
    - ${databaseSg.status.?id.orValue('')}
    - ${computeSg.status.?id.orValue('')}
    - ${searchSg.status.?id.orValue('')}
```

Empty strings from excluded SGs are handled by ACK (it ignores empty entries
in the list if provided as optional inputs).

---

## Cross-RGD SG Reference Pattern

When the Database tier needs to reference the Foundation tier's base SG ID,
it uses the bridge ConfigMap pattern (validated in Test 7):

```
Foundation RGD → creates {name}-foundation-bridge ConfigMap
                 data.base_sg_id = ${baseSg.status.id}

Database RGD   → externalRef reads {foundation-name}-foundation-bridge
                 uses bridgeData.data.base_sg_id as ingressRule source SG
```

This avoids hardcoding SG IDs and decouples tier lifecycle.

---

## Summary of Findings

| Question | Answer |
|----------|--------|
| Can KRO add conditional array entries in a single SG? | **No** — templates are static YAML |
| Can multiple SG resources work with includeWhen? | **Yes** — Pattern A, preferred |
| Can schema-driven rule injection work? | **Yes** — Pattern B, with caveats |
| Can one route table grow as tiers are added? | **No** — same limitation |
| Can separate route tables per tier work? | **Yes** — Option 2 recommended |
| Can cross-RGD SG IDs be shared? | **Yes** — via bridge ConfigMap pattern |

The design conclusion: **gen3-kro modular RGDs should use Pattern A (multiple
SGs with includeWhen) and Route Table Option 2 (pre-built with natEnabled gate).
This gives per-tier SG isolation, accurate rule auditing, and no conditional
array limitations.**

---

## gen3-kro Production Patterns (from AwsGen3Infra1Flat)

This section documents the **exact** SG and RouteTable patterns used in the
production `AwsGen3Infra1Flat` RGD. These patterns are what the modular
7-tier design (Plan 02) must replicate across tiers.

### Production SecurityGroups

gen3-kro creates **two** SecurityGroups, both always present (no `includeWhen`):

```yaml
# 1. EKS control-plane SecurityGroup
- id: eksSecurityGroup
  template:
    apiVersion: ec2.services.k8s.aws/v1alpha1
    kind: SecurityGroup
    spec:
      vpcID: ${vpc.status.?vpcID}          # NOT vpcRef — uses status field
      description: "EKS cluster SG"
      ingressRules:
        - fromPort: 443
          toPort: 443
          ipProtocol: tcp
          ipRanges:
            - cidrIP: ${schema.spec.vpcCIDR}
              description: "HTTPS from VPC"
        - fromPort: 10250
          toPort: 10250
          ipProtocol: tcp
          ipRanges:
            - cidrIP: ${schema.spec.vpcCIDR}
              description: "Kubelet from VPC"

# 2. Aurora PostgreSQL SecurityGroup — references eksSecurityGroup via userIDGroupPairs
- id: auroraSecurityGroup
  template:
    apiVersion: ec2.services.k8s.aws/v1alpha1
    kind: SecurityGroup
    spec:
      vpcID: ${vpc.status.?vpcID}
      description: "Aurora PostgreSQL SG"
      ingressRules:
        - fromPort: 5432
          toPort: 5432
          ipProtocol: tcp
          userIDGroupPairs:
            - groupID: ${eksSecurityGroup.status.?id}   # SG-to-SG rule (intra-RGD)
              description: "PostgreSQL from EKS nodes"
```

**Key ACK field facts**:
- SGs use `spec.vpcID: ${vpc.status.?vpcID}` (direct ID — NOT `spec.vpcRef`)
- `status.?id` is the SG group ID (e.g., `sg-0abc123...`) — used in `userIDGroupPairs.groupID`
- Cross-RGD equivalent: `groupID: ${bridgeData.data.eks_sg_id}` (from bridge ConfigMap)

### Production RouteTables

gen3-kro creates **three** RouteTables, all always present:

```yaml
# 1. Public RouteTable — routes to IGW
- id: publicRouteTable
  template:
    apiVersion: ec2.services.k8s.aws/v1alpha1
    kind: RouteTable
    spec:
      vpcID: ${vpc.status.?vpcID}
      routes:
        - destinationCIDRBlock: "0.0.0.0/0"
          gatewayID: ${igw.status.?internetGatewayID}   # IGW status field

# 2. Private RouteTable — routes to NAT Gateway
- id: privateRouteTable
  template:
    apiVersion: ec2.services.k8s.aws/v1alpha1
    kind: RouteTable
    spec:
      vpcID: ${vpc.status.?vpcID}
      routes:
        - destinationCIDRBlock: "0.0.0.0/0"
          natGatewayID: ${natGateway1.status.?natGatewayID}

# 3. Database RouteTable — isolated (no routes = local VPC only)
- id: dbRouteTable
  template:
    apiVersion: ec2.services.k8s.aws/v1alpha1
    kind: RouteTable
    spec:
      vpcID: ${vpc.status.?vpcID}
      routes: []           # No routes — db subnets can only reach VPC-local addresses
```

**Subnet association**: Subnets reference route tables via K8s name refs:
```yaml
spec:
  routeTableRefs:
    - from:
        name: ${publicRouteTable.metadata.name}    # K8s name ref (NOT routeTableID)
```

**Key ACK field facts**:
- IGW uses `spec.vpcRef.from.name: ${vpc.metadata.name}` for attachment (K8s name ref)
- IGW status field: `status.?internetGatewayID` (used in route `gatewayID`)
- NAT GW status field: `status.?natGatewayID` (used in route `natGatewayID`)
- RT status field: `status.?routeTableID` (used in subnet `routeTableRefs` — indirect, via name ref)

### Mapping to Modular 7-Tier Architecture (Plan 02)

Based on production patterns and capability test findings:

| Tier | SGs Created | Route Tables | Cross-Tier Bridge |
|------|-------------|--------------|-------------------|
| Foundation | `base-sg` (ports 443+10250 — EKS control-plane style) | `public-rt` (IGW route), `basic-private-rt` (no NAT) | Publishes `base_sg_id`, `vpc_id` |
| Network | — | `nat-private-rt` (NAT route, replaces basic) | Publishes `nat_rt_id` |
| Database | `db-sg` (port 5432 from Foundation base-sg via `userIDGroupPairs`) | `db-rt` (isolated, no routes) | Publishes `db_sg_id` |
| Compute | `compute-sg` (API/gRPC from private subnet) | — (uses nat-private-rt) | Publishes `compute_sg_id` |
| Search | `search-sg` (OpenSearch from compute-sg) | — | — |
| AppIAM | — | — | Publishes IAM role ARNs |
| Monitoring | — | — | — |

**Pattern A** is the implementation strategy for all tier SGs:
- Each tier creates its own SG with `includeWhen` guarding the whole resource
- Cross-tier SG references flow through bridge ConfigMaps (Test 7 pattern)
- `dbSg.spec.ingressRules[].userIDGroupPairs[].groupID = bridgeData.data.base_sg_id`
