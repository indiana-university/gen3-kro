# Spoke1 Fleet Directory

This directory contains all KRO instance Custom Resources (CRs) and values files
for the `spoke1` spoke cluster. ArgoCD's `fleet-instances` ApplicationSet picks up
every `*.yaml` here (recursively, excluding `values.yaml` and `cluster-values.yaml`)
and applies them to the `spoke1` destination cluster.

---

## Directory Layout

```
argocd/fleet/spoke1/
├── README.md                                   ← this file
├── infrastructure/
│   ├── infrastucture-values.yaml               ← ConfigMap of all infra knobs (sync-wave 14)
│   └── instances.yaml                          ← 10 KRO infrastructure CRs (waves 15–25)
├── cluster-level-resources/
│   ├── cluster-values.yaml                     ← $values ref for instances chart (excluded from recurse)
│   └── app.yaml                                ← AwsGen3ClusterResources1 instance (wave 27)
└── spoke1dev.rds-pla.net/
    ├── values.yaml                             ← $values ref for gen3-helm chart (excluded from recurse)
    └── app.yaml                                ← AwsGen3Helm1 instance (wave 30)
```

---

## Deployment Order (ArgoCD Sync Waves)

| Wave | Resource | File | Description |
|------|----------|------|-------------|
| 14 | `ConfigMap/infrastructure-values` | `infrastructure/infrastucture-values.yaml` | All infra knobs; read by every RGD via `infrastructureConfig` externalRef |
| 15 | `AwsGen3Network1/gen3` | `infrastructure/instances.yaml` | VPC, subnets, SGs, KMS keys, route tables |
| 16 | `AwsGen3Dns1/gen3` | `infrastructure/instances.yaml` | Route53 hosted zone adoption + ACM cert + DNS validation |
| 16 | `AwsGen3Storage1/gen3` | `infrastructure/instances.yaml` | S3 buckets (logging, data, upload, usersync) |
| 20 | `AwsGen3Compute1/gen3` | `infrastructure/instances.yaml` | EKS managed nodegroups |
| 20 | `AwsGen3Database1/gen3` | `infrastructure/instances.yaml` | Aurora PostgreSQL cluster (thin + ESO secret) |
| 20 | `AwsGen3Search1/gen3` | `infrastructure/instances.yaml` | OpenSearch domain (+ optional Redis) |
| 24 | `AwsGen3OIDC1/gen3` | `infrastructure/instances.yaml` | EKS OIDC provider |
| 25 | `AwsGen3Advanced1/gen3` | `infrastructure/instances.yaml` | WAFv2 WebACL (feature-flagged) |
| 25 | `AwsGen3Messaging1/gen3` | `infrastructure/instances.yaml` | SQS queues (audit, ssjdispatcher) |
| 25 | `AwsGen3IAM1/gen3` | `infrastructure/instances.yaml` | 11 IRSA roles for gen3 services |
| 27 | `AwsGen3ClusterResources1/gen3` | `cluster-level-resources/app.yaml` | ALB controller, ESO, Karpenter, cert-manager, CoreDNS, etc. |
| 30 | `AwsGen3Helm1/gen3` | `spoke1dev.rds-pla.net/app.yaml` | gen3-helm ArgoCD Application |

KRO enforces a secondary ordering layer via **bridge ConfigMaps**: each RGD writes a
bridge when its AWS resources are Ready, and the next tier waits for that bridge via
`externalRef` before it can proceed. Sync-wave ordering alone cannot guarantee AWS
resource readiness — the bridge pattern is what makes the pipeline safe.

---

## The Infrastructure ConfigMap Pattern

### Why a ConfigMap instead of RGD schema fields?

The `infrastructure-values` ConfigMap (wave 14) carries every tunable parameter for
the spoke — VPC CIDRs, instance types, engine versions, bucket names, feature flags,
and region. All RGDs read it via a shared `externalRef`:

```yaml
- id: infrastructureConfig
  externalRef:
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: infrastructure-values
      namespace: spoke1
```

**Reasons for ConfigMap over RGD `spec` fields:**

1. **Single source of truth across 10+ RGDs.** If each instance carried its own
   `spec.vpcCidr`, `spec.dbEngineVersion`, etc., every value would have to be
   duplicated across 10 instance CRs and kept in sync. One ConfigMap eliminates drift.

2. **Operator-friendly editing.** An operator patching a value (e.g. Aurora max
   capacity) edits one file, commits, and every dependent RGD picks it up on the
   next ArgoCD sync. No KRO schema version bump needed.

3. **Compatibility with gen3-terraform outputs.** The Terraform stack that provisions
   the spoke EKS cluster can emit a ConfigMap as a Terraform output and ArgoCD can
   apply it — the same values file format works for both machine-generated and
   human-authored inputs.

4. **Clean RGD schema.** KRO instance specs are intentionally minimal (`name`,
   `namespace`, and a few structural overrides). The ConfigMap provides the
   dense operational config so the instance spec remains readable and stable.

5. **Feature flags work naturally.** Values like `advanced-waf-enabled: "false"` and
   `search-redis-enabled: "false"` toggle entire sub-graphs inside an RGD without
   changing the instance CR or the schema version.

### What values live here vs in the instance spec?

| Configuration | Where it lives | Why |
|---------------|---------------|-----|
| VPC CIDR, subnet CIDRs, AZs | `infrastructure-values` | Infra-tier, stable, shared |
| Aurora engine version, capacity | `infrastructure-values` | Operational knob |
| Feature flags (`waf-enabled`, `redis-enabled`) | `infrastructure-values` | Shared across RGDs |
| Bridge ConfigMap names | Instance `spec` (or RGD default) | Structural, per-instance |
| `name`, `namespace` | Instance `spec` | KRO requires them |
| `esoUseIRSA: true` | Instance `spec` (Database1 only) | IRSA vs K8s Secret toggle |

---

## Bridge ConfigMap Chain

Each infrastructure RGD publishes a bridge ConfigMap when its AWS resources are
Ready. Downstream RGDs consume these bridges via `externalRef`. This creates an
implicit dependency ordering that complements ArgoCD sync-waves:

```
Network1 → foundation-bridge (SG IDs, subnet IDs, KMS ARNs)
         ↓ (consumed by Database1, Search1, Compute1, IAM1)

Dns1     → dns-bridge (hosted-zone-id, acm-cert-arn, hostname)
         ↓ (consumed by Helm1 as acmBridge)

Storage1 → storage-bridge (bucket ARNs and names)
         ↓ (consumed by IAM1, Helm1)

Compute1 → compute-bridge (EKS cluster ARN, endpoint, CA, OIDC issuer)
         ↓ (consumed by IAM1, ClusterResources1, Helm1)

Database1 → database-bridge (Aurora endpoint, port, DB name, SM secret name)
          ↓ (consumed by Helm1)

Search1  → search-bridge (OpenSearch endpoint, domain ARN)
         ↓ (consumed by Helm1)

IAM1     → iam-bridge (11 IRSA role ARNs)
         ↓ (consumed by ClusterResources1, Helm1)

Messaging1 → messaging-bridge (SQS queue URLs)
           ↓ (consumed by Helm1)

Advanced1 → advanced-bridge (WAF ACL ARN or empty when WAF disabled)
          ↓ (consumed by Helm1)

ClusterResources1 → cluster-resources-bridge (ArgoCD app sync status)
                  ↓ (consumed by Helm1 readyWhen gating)

Helm1 creates the gen3-helm ArgoCD Application (final tier)
```

---

## ArgoCD Sources Architecture

The `fleet-instances` ApplicationSet uses `directory.recurse: true` to pick up all
`*.yaml` in the spoke directory, with two file exclusions:

```yaml
directory:
  recurse: true
  include: '*.yaml'
  exclude: '{values.yaml,cluster-values.yaml}'
```

**Why exclude `values.yaml` and `cluster-values.yaml`?**

Two of the KRO instance CRs (`AwsGen3Helm1` and `AwsGen3ClusterResources1`) are
multi-source ArgoCD Applications that reference a companion `$values` source. ArgoCD
resolves a bare filename like `values.yaml` as a Helm values file only within a
multi-source Application — if the fleet-instances ApplicationSet applied the file as
a raw Kubernetes object, it would fail (no `kind` field). The exclusion keeps these
companion files from being directly applied while still making them available to the
multi-source applications that reference them.

### ClusterResources1 multi-source

`cluster-level-resources/app.yaml` (`AwsGen3ClusterResources1`) creates an ArgoCD
Application that deploys the **application-sets Helm chart** to the spoke cluster.
This chart installs addon ApplicationSets (ALB controller, ESO, Karpenter, etc.)
and their cluster-scoped configurations.

`cluster-level-resources/cluster-values.yaml` is the `$values` override file —
it contains per-spoke toggles (`alb-controller.enabled: true`, Karpenter node pool
settings, etc.) that are layered over the Helm chart defaults.

### Helm1 multi-source (gen3-helm)

`spoke1dev.rds-pla.net/app.yaml` (`AwsGen3Helm1`) creates an ArgoCD Application
that deploys **gen3-helm** to the spoke EKS cluster. The application is parameterised
in two layers:

1. **`$values` ref** — `spoke1dev.rds-pla.net/values.yaml`: operator-curated service
   enablement flags and static config (hostname, environment, ESO secret names, etc.)

2. **`helm.parameters` injected by KRO bridges** (Layer 2): ARNs, endpoints, bucket
   names, and the WAF ACL ARN are resolved at runtime from bridge ConfigMaps and
   injected as Helm parameters. These override any values from layer 1.

This two-layer approach means Layer 1 is safe to commit (no secrets, no ARNs), and
Layer 2 is computed at runtime by KRO from actual AWS resource outputs.

---

## Compatibility with gen3-helm and gen3-terraform

### gen3-helm

`spoke1dev.rds-pla.net/values.yaml` follows the same structure as a standard
gen3-helm `values.yaml`. An operator migrating from a standalone gen3-helm deployment
can take their existing values file, remove any hardcoded ARNs/endpoints (those are
injected by KRO), and place it here. The `global.hostname`, `global.environment`,
`global.postgres.*`, and per-service `externalSecrets` keys are all standard
gen3-helm fields.

The key difference is that fields like `global.aws.account`, the ALB ARN,
OpenSearch endpoint, IAM role ARNs, and WAF ACL ARN are **not** set in the values
file — they are injected as `helm.parameters` by `AwsGen3Helm1` using values read
from bridge ConfigMaps at reconciliation time.

### gen3-terraform (Terraform/Terragrunt outputs)

When the spoke was originally provisioned by a separate Terraform stack
(e.g. gen3-terraform or spoke-specific Terragrunt), that stack's outputs can be
expressed as a ConfigMap in the same format as `infrastucture-values.yaml`. An
operator bridge between the two systems is:

```bash
# Generate infrastructure-values from Terraform outputs
terraform output -json | jq -r '...' > infrastucture-values.yaml
```

The ConfigMap-based input design was chosen precisely to support this workflow: the
gen3-kro KRO layer can adopt pre-existing AWS resources (using ACK adoption policy)
and read their identifiers from a Terraform-generated ConfigMap, rather than
requiring gen3-kro to own the full AWS resource lifecycle.

---

## Adding a New Spoke

1. Create `argocd/fleet/<spoke-name>/` mirroring this directory structure.
2. Copy `infrastucture-values.yaml` and update all values for the new account.
3. Copy `instances.yaml` — instance CRs are self-contained; change `namespace:`.
4. Copy `cluster-level-resources/` and update `cluster-values.yaml` for the spoke.
5. Copy `<hostname>/` folder; update `values.yaml` with spoke-specific gen3-helm config.
6. Register the spoke cluster in ArgoCD with the required annotations
   (`enable_infra_instances: "true"`, `fleet_repo_url`, etc.).
7. Create the spoke namespace (`kubectl create namespace <spoke-name>`).
8. ArgoCD will pick up the new directory and deploy all waves automatically.

See [spoke-onboard prompt](../../../.github/prompts/spoke-onboard.prompt.md) and
[spoke-prerequisites doc](../../../docs/spoke-prerequisites.md) for full instructions.
