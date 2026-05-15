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

Deployment is split to avoid the spoke-role and CSOC-OIDC dependency loop.

| Phase | Context | Tool | Creates |
|-------|---------|------|---------|
| 1 | Host | Terragrunt | Spoke workload IAM roles |
| 2 | Container/WSL | Terraform | CSOC VPC, EKS, ArgoCD, ACK/ArgoCD roles, bootstrap AppSet |
| 3 | ArgoCD | GitOps | Controllers, RGDs, CARM resources, spoke instances |

Spoke roles trust the CSOC account root plus an `ArnLike` condition for `*-csoc-role`, so they can be created before the exact CSOC role ARN exists.

## Terraform Modules

```text
terraform/env/aws/csoc-cluster
└── terraform/catalog/modules/csoc-cluster
    ├── aws-csoc
    │   ├── VPC + EKS
    │   ├── ACK source role
    │   ├── ArgoCD role
    │   └── ArgoCD Helm install
    └── argocd-bootstrap
        ├── ArgoCD cluster secret
        ├── Git repo secret
        └── bootstrap ApplicationSet
```

Host-side Terragrunt units in `terragrunt/live/aws/iam-setup` create spoke IAM before the CSOC cluster is applied.

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

The spoke role trust uses the CSOC account root as the principal and restricts the real caller with `aws:PrincipalArn = arn:aws:iam::<CSOC>:role/*-csoc-role`.

## Local CSOC

`scripts/kind-csoc.sh` creates a host-based Kind CSOC for RGD iteration. It uses the same bootstrap manifests and `argocd/spokes/spoke1` values, but injects AWS credentials into the `ack` namespace because Kind has no EKS OIDC provider.

See `docs/local-csoc-guide.md` for local operations.
