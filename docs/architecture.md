# Architecture

The platform uses one CSOC EKS cluster as the control plane. ArgoCD reconciles this repo, KRO turns high-level Gen3 instances into composed resources, and ACK controllers create AWS resources in CSOC and spoke accounts.

Diagram sources live in `docs/diagrams/`.

## Control Plane

```text
CSOC account
└── EKS cluster ({csoc_alias}-csoc-cluster)
    ├── ArgoCD
    ├── KRO controller
    ├── ACK controllers
    ├── External Secrets
    └── KRO ResourceGraphDefinitions

Spoke accounts
└── VPC, EKS, RDS, S3, IAM, and Gen3 platform resources managed through ACK
```

| Component | Role |
|-----------|------|
| ArgoCD | Reconciles `argocd/` from git |
| KRO | Defines and reconciles composed infrastructure APIs |
| ACK | Manages AWS resources as Kubernetes CRs |
| ResourceGraphDefinitions | Gen3 infrastructure schemas under `argocd/csoc/kro` |
| External Secrets | Syncs AWS Secrets Manager values into Kubernetes |

## Deployment Model

Deployment is Terragrunt-first. Terraform implements modules; Terragrunt
orchestrates environment ordering so the CSOC role exists before spoke IAM is
planned.

| Phase | Context | Tool | Creates |
|-------|---------|------|---------|
| 1 | Host or container | Terragrunt + Terraform | Operator access |
| 2 | Host or container | Terragrunt + Terraform | CSOC VPC, EKS, and OIDC |
| 3 | Host or container | Terragrunt + Terraform | Controller IAM and Argo CD install |
| 4 | Host or container | Terragrunt + Terraform | Per-spoke IAM and CSOC spoke access |
| 5 | Host or container | Terragrunt + Terraform | GitOps and fleet bootstrap |
| 6 | ArgoCD | GitOps | Controllers, RGDs, CARM resources, spoke instances |

Spoke roles trust the exact CSOC controller role ARN emitted by controller IAM.
Optional manual access trusts only the exact operator role ARNs exported by
operator IAM.

## Terraform Modules

```text
terragrunt/live/aws/
├── operators-iam
│   └── aws-csoc-operator-iam -> aws-csoc-operator-iam
├── csoc-cluster-core
│   ├── aws-csoc-cluster -> aws-csoc-cluster
│   ├── aws-csoc-controller-iam -> aws-csoc-controller-iam
│   └── gitops-argocd-install -> gitops-argocd-install
└── spoke-fleet-update
    ├── aws-spoke-access-iam-<alias> -> aws-spoke-access-iam
    ├── aws-csoc-to-spoke-access -> aws-csoc-to-spoke-access
    └── gitops-argocd-bootstrap -> gitops-argocd-bootstrap
```

## ArgoCD Chain

```text
bootstrap ApplicationSet
└── bootstrap Application -> argocd/bootstrap
    ├── csoc-controllers -> self-managed-kro, ack-*, external-secrets
    ├── csoc-kro -> recursive argocd/csoc/kro RGD sync
    ├── multi-account -> per-spoke namespaces, CARM wiring, and secret-writer SAs
    └── fleet-instances -> kro-aws-instances per spoke
```

| Wave | Resource | Notes |
|------|----------|-------|
| -30 | KRO controller | Required before RGDs |
| -20 | `csoc-controllers` | Generates controller AppSets |
| 1 | ACK controllers | Required before ACK-backed instances |
| 5 | `multi-account` | Cross-account namespace and secret-writer wiring |
| 10 | `csoc-kro` | Recursive RGD delivery |
| 15 | External Secrets | Workload secret provider |
| 30 | `fleet-instances` | Per-spoke KRO instances |

See `argocd/README.md` for the GitOps file contract.

## Cross-Account Trust

```text
ACK pod
└── IRSA -> {csoc_alias}-ack-controller-role
    └── sts:AssumeRole -> <spoke>-ack-controller-access-role
        └── AWS APIs in spoke account
```

The spoke trust also accepts the exact subset of enabled operator roles whose
configuration sets `allow_spoke_access`. It never trusts account root or a
wildcard role-name pattern.

## Local CSOC

`scripts/kind-csoc.sh` creates a host-based Kind CSOC for RGD iteration. It uses the same bootstrap manifests and `argocd/spokes/spoke1` values, but injects AWS credentials into the `ack` namespace because Kind has no EKS OIDC provider.

See `docs/local-csoc-guide.md` for local operations.
