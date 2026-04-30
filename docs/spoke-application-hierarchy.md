# Spoke Application Hierarchy

How ArgoCD deploys Gen3 infrastructure and services to spoke clusters via KRO
ResourceGraphDefinitions.

## Application Flow (KRO-driven)

```
fleet-instances (ApplicationSet on CSOC)
  └─ spoke1-fleet-instances  (Application — picks up argocd/fleet/spoke1/**)
       ├── infrastructure/    KRO infra tier instances   (waves 15-25)
       ├── cluster-level-resources/  ClusterResources1 + Helm1 CRs  (waves 27-30)
       └── {hostname}/        per-hostname instances
```

All KRO instance CRs for a spoke live under `argocd/fleet/{spoke-name}/` and
are applied by a single ArgoCD Application per spoke. ArgoCD recursively picks
up every `*.yaml` file, excluding `values.yaml` and `cluster-values.yaml`
(operator preference files served as `$values` refs to multi-source Applications).

## KRO Instance → ArgoCD Application Chain

KRO instance CRs are CSOC-native CRDs (not workloads). Each instance, when
reconciled, creates downstream Kubernetes resources — including ArgoCD
Application CRs for spoke-targeted deployments.

### Infrastructure tier instances (waves 15-25)

| CR Kind | Wave | Creates |
|---------|------|---------|
| AwsGen3Network1 | 15 | VPC, subnets, SGs, KMS keys, route tables |
| AwsGen3Dns1 | 16 | Route53 zone adoption, ACM cert, DNS validation |
| AwsGen3Storage1 | 16 | S3 buckets (logging, data, upload, manifest, dashboard) |
| AwsGen3Compute1 | 20 | EKS cluster + managed node group + add-ons |
| AwsGen3Database1 | 20 | Aurora PostgreSQL Serverless v2 + ESO secret |
| AwsGen3Search1 | 20 | OpenSearch domain + optional ElastiCache Redis |
| AwsGen3OIDC1 | 24 | IAM OIDC provider for spoke EKS |
| AwsGen3Advanced1 | 25 | WAFv2 WebACL |
| AwsGen3Messaging1 | 25 | SQS queues |
| AwsGen3AppIAM1 | 25 | IRSA roles (fence, audit, ALB controller, Karpenter, …) |

### Cluster-level and app instances (waves 27-30)

| CR Kind | Wave | Creates |
|---------|------|---------|
| AwsGen3ClusterResources1 | 27 | ArgoCD cluster Secret (spoke registration) + ArgoCD Application deploying `gen3-helm/cluster-level-resources` to spoke |
| AwsGen3Helm1 | 30 | ArgoCD Application deploying `gen3-helm/gen3` umbrella chart to spoke |

## File Layout

```
argocd/
├── bootstrap/
│   ├── csoc-addons.yaml         ← KRO + ACK controllers ApplicationSet
│   ├── ack-multi-acct.yaml      ← ACK CARM multi-account ApplicationSet
│   └── fleet-instances.yaml     ← KRO instance CRs ApplicationSet (wave 30)
├── charts/
│   └── resource-groups/templates/  ← RGD definitions (one file per tier)
└── fleet/
    └── spoke1/
        ├── infrastructure/      ← Infra tier KRO instances
        │   ├── instances.yaml
        │   └── infrastucture-values.yaml  ← infrastructure-values ConfigMap
        ├── cluster-level-resources/
        │   ├── app.yaml         ← AwsGen3Helm1 instance (wave 30)
        │   └── cluster-values.yaml  ← operator values for cluster-level-resources chart
        └── spoke1dev.rds-pla.net/
            ├── app.yaml         ← AwsGen3ClusterResources1 instance (wave 27)
            └── values.yaml      ← operator values for gen3-helm chart
```

## Values Architecture (Multi-Source)

Both `AwsGen3ClusterResources1` and `AwsGen3Helm1` create multi-source ArgoCD
Applications:

```
Source 1: helm chart repo   (gen3-helm at master)
Source 2: values repo ref   (this repo — $values)
           └── values read from argocd/fleet/{spoke}/{path}/
```

Operator preference files (`values.yaml`, `cluster-values.yaml`) are excluded
from ArgoCD's recursive pickup and served only as `$values` refs.

## Key Architecture Points

- All KRO instance CRs live on the CSOC cluster (namespace = spoke name).
- ArgoCD Applications created by KRO target the spoke cluster via
  `destination.name: {spoke-name}-spoke` (ArgoCD cluster registration).
- Infrastructure outputs (Aurora endpoint, IRSA ARNs, S3 buckets, WAF ARN)
  flow through bridge ConfigMaps between KRO tiers and into `helm.parameters`.
- DB passwords stay in AWS Secrets Manager — consumed on the spoke via
  External Secrets Operator.
- The gen3-helm `cluster-level-resources` app-of-apps chart deploys
  cluster-wide Helm releases (ALB controller, Karpenter, cert-manager, etc.)
  directly to the spoke.
