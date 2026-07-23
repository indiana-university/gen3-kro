# Security

Security model, IAM boundaries, credential flow, and verification guidance for
the EKS cluster management platform.

## IAM architecture

The platform separates human access, CSOC controller identity, and spoke
resource access:

```text
Existing IAM user + MFA
└── exact assignment -> <csoc_alias>-csoc-operator-<role_key>
    ├── explicit EKS access entry -> CSOC Kubernetes authorization
    └── optional exact trust -> <spoke_alias>-<role_key>-access-role

ACK service account
└── IRSA -> <csoc_alias>-ack-controller-role
    └── sts:AssumeRole -> <spoke_alias>-ack-controller-access-role
        └── AWS APIs in the spoke account
```

IAM users are external. Terraform may manage their virtual MFA devices and
aggregate assume-role policies, but never creates or deletes users.

## Operator roles

`aws-csoc-operator-iam` creates independently enabled role functions:

| Role key | IAM permissions | EKS authorization | Spoke access |
| --- | --- | --- | --- |
| `infrastructure-admin` | Existing infrastructure provisioning policy, with exact configured spoke role ARNs | `AmazonEKSClusterAdminPolicy`, cluster scope | Enabled |
| `platform-operator` | Caller identity, EKS discovery/description, and operational CloudWatch Logs reads | `AmazonEKSAdminPolicy`, cluster scope | Disabled |

`platform-operator` is disabled until a user or exact external principal is
assigned. An enabled role must have at least one exact principal. Human trust
requires MFA and limits MFA age to the role session duration.

Each user receives one inline `sts:AssumeRole` policy containing only the
enabled roles assigned to that user. The account-root fallback has been
removed.

The cluster consumes enabled role outputs as explicit EKS access entries and
sets `enable_cluster_creator_admin_permissions = false`. EKS access policies
authorize Kubernetes API actions; they do not grant AWS IAM permissions.

## Cross-account trust

Every spoke role trust policy names concrete principals:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ExactCSOCSourceRole",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<CSOC_ACCOUNT_ID>:role/<CSOC_ALIAS>-ack-controller-role"
      },
      "Action": "sts:AssumeRole"
    },
    {
      "Sid": "ExactOperatorManualAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::<CSOC_ACCOUNT_ID>:role/<CSOC_ALIAS>-csoc-operator-infrastructure-admin"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

The optional operator statement is omitted when no operator role is approved
for spoke access. There is no account-root principal, `ArnLike` wildcard, or
ExternalId. ACK does not pass an ExternalId during `sts:AssumeRole`.

The inverse CSOC permission policy also enumerates exact spoke role ARNs:
`<spoke_alias>-ack-controller-access-role`. The statement is omitted when no
spokes are enabled.

## Controller identities

| Physical name | Trust | Purpose |
| --- | --- | --- |
| `<csoc_alias>-ack-controller-role` | EKS OIDC and selected ACK service accounts | ACK CSOC identity and spoke assumption |
| `<csoc_alias>-argocd-controller-role` | EKS OIDC or EKS capability service | Argo CD AWS access |
| `<csoc_alias>-kro-controller-role` | EKS capability service | AWS-managed KRO capability |
| `<csoc_alias>-external-secrets-role` | EKS Pod Identity | Secret synchronization |

Argo CD protocol objects keep their integration names: namespace and Helm
release `argocd`, standard service accounts, repository secrets, and cluster
secrets.

## Human credential flow

1. Apply a reviewed `aws-csoc-operator-iam` plan.
2. Register any new virtual MFA device using the sensitive
   `mfa_enrollment` Terraform output.
3. Run `bash scripts/operator-profile.sh` to write ignored, non-secret role and
   MFA ARN mappings to `outputs/aws-csoc-operator-iam.json`.
4. Run `bash scripts/mfa-session.sh <MFA_CODE> [--role-key ROLE_KEY]`.
5. The script obtains a short-lived session for the selected assigned role and
   writes only that session to the isolated devcontainer credentials directory.

Terraform does not manage local AWS config/profile files. The explicit profile
script is read-only against Terraform state and emits no enrollment seed.

## Secrets

- Real `config/shared.auto.tfvars.json`, account IDs, secret identifiers, PEM
  files, state, plans, generated stack trees, and `outputs/` remain ignored.
- GitHub App credentials are pushed to AWS Secrets Manager by the explicit
  `scripts/ssm-repo-secrets` workflow.
- Argo CD repository secrets contain only integration payloads and retain their
  protocol-defined names.
- Sensitive Terraform outputs must never be copied into documentation, logs, or
  commits.

## Network and audit

Cross-account ACK operations use AWS STS and service endpoints; no VPC peering
or Transit Gateway is required solely for the trust chain. EKS API reachability
and AWS network policy remain environment concerns.

Before production use, verify:

- [ ] Only existing IAM users are referenced; Terraform plans no user create or delete.
- [ ] Every enabled operator role has exact principals and MFA is required for humans.
- [ ] User assume policies contain only assigned role ARNs.
- [ ] Cluster-creator administration is disabled and explicit EKS entries match enabled roles.
- [ ] Spoke trust contains exact controller/operator role ARNs and no root/wildcard principal.
- [ ] Spoke role and policy names include the role key and chunk index where applicable.
- [ ] Infrastructure-admin contains only configured spoke role ARNs.
- [ ] GitHub credentials and MFA enrollment data are absent from git and logs.
- [ ] `kubectl auth can-i` confirms the intended difference between
  `infrastructure-admin` and `platform-operator`.
