# Fleet stack

This stack onboards one selected spoke while maintaining CSOC-wide access and
GitOps metadata. It contains three ordered units:

1. `aws-spoke-access-iam-<alias>` runs with the selected spoke AWS profile and
   creates its ACK access role, trusting the exact CSOC controller role and
   exact approved operator roles from their respective states.
2. `aws-csoc-to-spoke-access` runs in the CSOC account and updates the source role's
   inline policy with exact enabled-spoke role ARNs.
3. `gitops-argocd-bootstrap` connects to the CSOC cluster, creates optional repo
   secrets and CSOC/spoke generator secrets, then installs the first bootstrap
   ApplicationSet.

After bootstrap, Argo CD, KRO, and ACK own ongoing controller, RGD, spoke
infrastructure, and application reconciliation. Terraform should not take over
those resources.

## Architecture

```text
Stage 1 - core stack   Stage 2 - cluster unit   Stage 3 - controller IAM unit   Stage 4 - install or fleet entry   Stage 5 - spoke IAM unit   Stage 6 - spoke access unit   Stage 7 - GitOps bootstrap unit
Orchestration order: earlier ──────────────────────→ later

┌──────────────────┐   ┌────────────────────┐   ┌───────────────────────────┐       ┌──────────────────────┐
│ Stack: csoc-cluster-core ├──→┤ Unit: aws-csoc-cluster ├──→┤ Unit: aws-csoc-controller-iam ├──→┬──→┤ Unit: gitops-argocd-install ├───────────────────────────────────────────────────────────────→┐
└──────────────────┘   └────────────────────┘   └───────────────────────────┘   │   └──────────────────────┘                                                                │
                                                                                │                                                                                           │
                                                                                │   ┌──────────────┐   ┌─────────────────────────────────────┐   ┌─────────────────────────┐   │   ┌───────────────────────────────┐
                                                                                └──→┤ Stack: spoke-fleet-update ├──→┤ Unit: aws-spoke-access-iam-<alias> ├──→┤ Unit: aws-csoc-to-spoke-access ├──→┴──→┤ Unit: gitops-argocd-bootstrap │
                                                                                    └──────────────┘   └─────────────────────────────────────┘   └─────────────────────────┘       └───────────────────────────────┘
```

## Spoke selection

The stack reads enabled spokes from `config/shared.auto.tfvars.json`. Set
`TG_SPOKE_ALIAS` whenever more than one is enabled:

```bash
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update plan
```

Only the selected spoke IAM unit is instantiated in a run. Onboard and review
each spoke IAM state separately. The CSOC access policy and Argo CD metadata are
built from the complete enabled-spoke set, so all referenced spoke roles should
exist before applying those shared units.

The spoke provider may use a spoke-specific profile/region, while its Terraform
backend uses the configured CSOC backend profile. The selected ACK permission
document comes from `iam/<alias>/ack/inline-policy.json`, falling back to
`iam/_default/ack/inline-policy.json`. Review it as part of every spoke plan.

## Private repository credentials

Public repositories require no repository secret. For private repositories,
`ssm_repo_secret_names` points to AWS Secrets Manager despite the legacy field
name. Follow [`config/README.md`](../../../../config/README.md) for the
supported schema. Secret payloads enter both Terraform state and Kubernetes
Secrets, so backend and cluster access must be restricted.

## Focused planning

```bash
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update plan aws-spoke-access-iam
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update plan aws-csoc-to-spoke-access
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update plan gitops-argocd-bootstrap
```

Review the selected spoke role trust/policies, verify it has no account-root or
wildcard path, review the full CSOC assume-role ARN set, and review Argo CD
secret/ApplicationSet changes before applying. For removal,
first stop or remove GitOps objects that depend on the spoke, then review shared
bootstrap/access updates and the selected spoke IAM destroy plan. Do not destroy
CSOC core while fleet state still depends on its outputs.
