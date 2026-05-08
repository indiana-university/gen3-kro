# Agent Task: Refine Minimal AWS Deployment Requirements for Gen3 Build

## Local Workspace Context

You are working in the dev container at:

- Primary workspace repo: `/workspaces/gen3-kro`
- Gen3 Build reference repo: `/workspaces/gen3-kro/references/gen3-build`
- Gen3 umbrella chart to analyze: `/workspaces/gen3-kro/references/gen3-build/helm/gen3`
- Gen3 Build subcharts: `/workspaces/gen3-kro/references/gen3-build/helm`
- Gen3 Build reference repo: `/workspaces/gen3-kro/references/gen3-build`
- Cluster-level resources chart in Gen3 Build: `/workspaces/gen3-kro/references/gen3-build/helm/cluster-level-resources`
- KRO resource group definitions in this repo: `/workspaces/gen3-kro/argocd/csoc/kro/aws-rgds`
- Existing spoke values examples:
  - `/workspaces/gen3-kro/argocd/spokes`

Treat `references/gen3-build` as local reference repositories. Prefer reading from them directly instead of using web search.

## Goal

Determine the minimal set of Gen3 services required for a functional AWS deployment using the Gen3 umbrella Helm chart.

Focus on:

- The umbrella chart at `/workspaces/gen3-kro/references/gen3-build/helm/gen3`
- Its default `values.yaml`
- Its `Chart.yaml` dependencies
- Subchart values, templates, and documentation under `/workspaces/gen3-kro/references/gen3-build/helm`
- Any Gen3 Build cluster-level resource assumptions relevant to AWS
- Any KRO/RGD assumptions in `/workspaces/gen3-kro/argocd/csoc/kro/aws-rgds`

Do not simply list every chart dependency. Identify:

- Services enabled by default
- Services that are required indirectly by default-enabled services
- Services that are operationally compulsory for a minimal Gen3 deployment even if not obvious from default values
- Dependencies or prerequisites implied by templates/docs but not explicitly configured in default values
- Services enabled by default that may be optional for a truly minimal deployment
- Services disabled by default and excluded from the minimal deployment

## Required Deliverables

Create the deliverables under:

`/workspaces/gen3-kro/docs/minimal-aws/`

Use clear Markdown/YAML files. Do not put real secrets in any output.

### 1. Compulsory Services File

Create:

`/workspaces/gen3-kro/docs/minimal-aws/compulsory-gen3-services.md`

For each service, include:

- Service name
- Whether it is enabled by default in the Gen3 umbrella chart values
- Why it is required
- Direct chart dependencies or service dependencies
- External dependencies, such as PostgreSQL, Elasticsearch/OpenSearch, object storage, secrets, IAM, or networking
- Notes on whether it can be disabled in a minimal deployment

Clearly distinguish these categories:

- Default-enabled services
- Services required because another service depends on them
- Optional services that are enabled by default but may not be strictly required
- Services disabled by default and excluded from the minimal deployment

### 2. Minimal AWS Values Map File

Create:

`/workspaces/gen3-kro/docs/minimal-aws/minimal-aws-values.yaml`

This should be a proposed minimal `values.yaml` map for deploying the compulsory services on AWS.

Include:

- Explicit `enabled` settings for all compulsory services
- Explicit disabled settings for non-minimal services
- Required `global` values used by multiple services
- Configuration stubs/placeholders for required external dependencies
- Database configuration for each service that requires PostgreSQL or another database
- Search configuration for Elasticsearch/OpenSearch-compatible services
- S3 or object-storage configuration where required
- Hostname, TLS, ingress/load balancer, and external URL configuration
- Secret references or placeholders for credentials
- IAM/service-account annotation placeholders where services require IRSA
- Any prerequisites that are not directly stated in the chart but are required for a real AWS deployment

Use placeholders only, for example:

```yaml
hostname: example.org
fence:
  db:
    host: <rds-endpoint>
    password: <external-secret-ref>
```

### 3. AWS Prerequisites Not Covered By RGD

Create:

`/workspaces/gen3-kro/docs/minimal-aws/aws-prerequisites-not-in-rgd.md`

Compare the minimal Gen3 Build requirements against the KRO/RGD resources currently defined in:

- `/workspaces/gen3-kro/argocd/csoc/kro/aws-rgds/gen3/v1/Phase2/platform-iam1-rg.yaml`
- `/workspaces/gen3-kro/argocd/csoc/kro/aws-rgds/gen3/v1/Phase3/platform-helm1-rg.yaml`
- `/workspaces/gen3-kro/argocd/csoc/kro/aws-rgds/gen3/v1/Phase4/app-helm1-rg.yaml`
- Other nearby resource-group templates as needed

List AWS prerequisites that appear required for a real minimal deployment but are not currently included, generated, or surfaced by the RGD flow.

Consider:

- Route 53 hosted zone or DNS delegation
- ACM certificates
- External Secrets or Secrets Manager entries
- RDS databases and users
- OpenSearch or Elasticsearch
- S3 buckets and bucket policies
- IAM roles and IRSA policies
- KMS keys
- VPC endpoints, NAT, egress, or security groups
- ALB ingress annotations and load balancer assumptions
- Any bootstrap secrets required before Helm can converge

For each item, include:

- Requirement
- Why Gen3 needs it
- Evidence from chart values/templates/docs
- Whether current RGD appears to cover it
- Suggested place to add or surface it, if known

### 4. Unified EKS Mode Reconfiguration Notes

Create:

`/workspaces/gen3-kro/docs/minimal-aws/unified-modes-reconfiguration.md`

List the changes needed to run the minimal AWS deployment in either EKS Auto Mode
or standard/self-managed add-on mode from the same RGD stack.

Consider:

- Which cluster-level resources conflict with Auto Mode and must be force-disabled by the RGD
- Which controllers should stay ordinary ConfigMap toggles with defaults matching the chart
- Whether Karpenter, node classes, or node pools should be disabled in Auto Mode and optional in standard mode
- Whether AWS Load Balancer Controller is community-managed today or needs a future built-in Auto Mode option
- EBS CSI, VPC CNI, CoreDNS, kube-proxy, metrics-server, and other add-on assumptions
- Service account IAM role changes
- StorageClass changes
- Ingress/load balancer changes
- Any RGD or values changes needed in `gen3-kro`
- Any chart values changes needed in `gen3-build`

For each change, include:

- Current assumption
- Auto Mode-compatible assumption
- Standard/self-managed-compatible assumption
- Files likely affected
- Whether it is required, recommended, or optional

## Investigation Guidance

Start with these files:

- `/workspaces/gen3-kro/references/gen3-build/helm/gen3/Chart.yaml`
- `/workspaces/gen3-kro/references/gen3-build/helm/gen3/values.yaml`
- `/workspaces/gen3-kro/references/gen3-build/helm/gen3/templates`
- `/workspaces/gen3-kro/references/gen3-build/helm/*/values.yaml`
- `/workspaces/gen3-kro/references/gen3-build/helm/*/templates`
- `/workspaces/gen3-kro/references/gen3-build/docs`
- `/workspaces/gen3-kro/references/gen3-build/helm/cluster-level-resources/values.yaml`
- `/workspaces/gen3-kro/references/gen3-build/helm/cluster-level-resources/templates`
- `/workspaces/gen3-kro/argocd/csoc/kro/aws-rgds`

Use `rg` for searches. Useful search terms include:

- `enabled: true`
- `condition:`
- `dependencies:`
- `postgres`
- `db:`
- `database`
- `elasticsearch`
- `opensearch`
- `s3`
- `bucket`
- `secret`
- `external-secret`
- `eks.amazonaws.com/role-arn`
- `ingress`
- `hostname`
- `global`
- `crossplane`
- `aws`

## Evidence Standard

Ground conclusions in local source evidence. When possible, cite file paths and line numbers in the Markdown deliverables.

Example:

```markdown
Evidence: `references/gen3-build/helm/fence/values.yaml`, `references/gen3-build/helm/fence/templates/deployment.yaml`
```

If a requirement is inferred rather than explicit, label it as inferred and explain the reasoning.

## Constraints

- Do not use real secrets, account IDs, hostnames, or ARNs.
- Do not modify Helm chart behavior unless explicitly asked.
- Keep generated files in `/workspaces/gen3-kro/docs/minimal-aws/`.
- Preserve unrelated local changes.
- Prefer local repository evidence over web research.
- If using Helm commands, render locally only. Do not deploy anything.

## Suggested Verification

After creating the files:

- Run `git diff --check` from `/workspaces/gen3-kro`
- Run YAML validation on `docs/minimal-aws/minimal-aws-values.yaml` if a YAML parser is available
- Optionally run `helm template` against `/workspaces/gen3-kro/references/gen3-build/helm/gen3` with the proposed values file to catch structural issues, but do not treat a successful render as proof that AWS prerequisites exist
