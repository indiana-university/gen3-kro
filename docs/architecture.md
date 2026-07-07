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
| 1 | Host or container | Terragrunt + Terraform | Developer identity |
| 2 | Host or container | Terragrunt + Terraform | CSOC VPC, EKS, OIDC, CSOC IAM roles |
| 3 | Host or container | Terragrunt + Terraform | Spoke workload IAM roles |
| 4 | Host or container | Terragrunt + Terraform | Argo CD install and bootstrap AppSet |
| 5 | ArgoCD | GitOps | Controllers, RGDs, CARM resources, spoke instances |

Spoke roles prefer exact trust to the CSOC source role ARN emitted by the
foundation unit. The account-root plus `ArnLike` trust remains as a compatibility
fallback for the deprecated IAM setup stack and state migration window.

## Terraform Modules

```text
terragrunt/live/aws/csoc
└── terraform/catalog/units
    ├── csoc-foundation -> terraform/catalog/modules/aws-csoc-foundation
    │   ├── VPC + EKS
    │   ├── ACK source role
    │   ├── ArgoCD role
    │   └── optional AWS-managed capabilities
    ├── spoke-iam -> terraform/catalog/modules/aws-spoke
    └── csoc-in-cluster-bootstrap -> terraform/catalog/modules/csoc-in-cluster-bootstrap
        ├── ArgoCD namespace, service accounts, and Helm install
        └── argocd-bootstrap submodule for repo/cluster secrets and AppSet
```

`terraform/catalog/modules/csoc-cluster` remains as the compatibility wrapper for
the old plain Terraform root until state migration is complete.

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
└── IRSA -> {csoc_alias}-csoc-role
    └── sts:AssumeRole -> <spoke>-spoke-role
        └── AWS APIs in spoke account
```

The preferred spoke role trust uses the exact `{csoc_alias}-csoc-role` ARN as
principal. The devcontainer role can remain trusted for scoped manual cleanup if
that operator path is required.

## Local CSOC

`scripts/kind-csoc.sh` creates a host-based Kind CSOC for RGD iteration. It uses the same bootstrap manifests and `argocd/spokes/spoke1` values, but injects AWS credentials into the `ack` namespace because Kind has no EKS OIDC provider.

See `docs/local-csoc-guide.md` for local operations.
