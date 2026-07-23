# AWS CSOC cluster

AWS-only foundation module for the CSOC control plane. It creates a VPC with
public and private subnets, optional NAT gateways, and an EKS cluster using the
pinned upstream VPC and EKS modules. It configures no Kubernetes or Helm
provider and creates no in-cluster resources.

Resource names are derived as `<csoc_alias>-csoc-vpc` and
`<csoc_alias>-csoc-cluster`. When availability zones are omitted, the first two
standard available zones are selected. Explicit subnet CIDRs take precedence;
otherwise CIDRs are derived from `vpc_cidr`. Private subnets receive internal
load-balancer and Karpenter discovery tags, and public subnets receive the
external load-balancer tag.

The module defaults to EKS Auto Mode, a public API endpoint, cluster-creator
administrator access, one shared NAT gateway, and disabled EKS control-plane
log types. Review those defaults against the environment's security and
availability requirements.

## Architecture

```text
Prerequisites/Dependencies
It is assumed that IAM identities for the account used to deploy the cluster has already been created by the aws-csoc-operator-iam module.

AWS VPC and EKS cluster resources for CSOC control plane.
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Module: aws-csoc-cluster                                                                                                                                                                                                    │
│                                                                                                                                     ┌─────────────────────────────────────────────────────────────────────────────────────┐ │
│                                                                                                                                     │ Module: terraform-aws-eks                                                           │ │
│                                                                                                                                     │                            ┌────────────────────────────────┐                       │ │
│                                                                                                                                     │                            │ Cluster IAM policy attachments │                       │ │
│                                                                                                                                     │                            │ ┌───────────────────────────┐  │                       │ │
│                                                                                                                                     │                            │ │ Cluster policy attachment │  │                       │ │
│                                                                                                                                     │ ┌──────────────────┐       │ └───────────────────────────┘  │       ┌─────────────┐ │ │
│ ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐       │ │ Cluster IAM role │──────→│ ┌───────────────────────────┐  │──────→│ EKS cluster │ │ │
│ │ Module: terraform-aws-vpc                                                                                                 │       │ └──────────────────┘       │ │ Compute policy attachment │  │       └─────────────┘ │ │
│ │                    ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐ │       │                            │ └───────────────────────────┘  │                       │ │
│ │                    │ VPC resources                                                                                      │ │       │                            │ ┌─────┐                        │                       │ │
│ │                    │ ┌──────────────────┐       ┌──────────────────────┐       ┌────────────────────┐                   │ │       │                            │ │ ... │                        │                       │ │
│ │                    │ │ Internet gateway │──────→│ Public default route │──────→│ Public route table │                   │ │       │                            │ └─────┘                        │                       │ │
│ │                    │ └──────────────────┘       └──────────────────────┘       └────────────────────┘                   │ │       │                            └────────────────────────────────┘                       │ │
│ │                    │ ┌─────────────────────┐       ┌─────────────────────────────────┐                                  │ │       │                                      ┌──────────────────────┐                       │ │
│ │                    │ │ Public subnets      │       │ Public route-table associations │                                  │ │       │ ┌────────────────────────────┐       │ Security-group rules │                       │ │
│ │                    │ │ ┌─────────────────┐ │       │ ┌───────────────┐               │                                  │ │       │ │ Security groups            │       │ ┌──────────────────┐ │                       │ │
│ │                    │ │ │ Public subnet 1 │ │       │ │ Association 1 │               │                                  │ │       │ │ ┌────────────────────────┐ │       │ │ Cluster API rule │ │                       │ │
│ │                    │ │ └─────────────────┘ │       │ └───────────────┘               │                                  │ │       │ │ │ Cluster security group │ │       │ └──────────────────┘ │                       │ │
│ │                    │ │ ┌─────────────────┐ │       │ ┌───────────────┐               │                                  │ │       │ │ └────────────────────────┘ │       │ ┌──────────────────┐ │                       │ │
│ │                    │ │ │ Public subnet 2 │ │──────→│ │ Association 2 │               │                                  │ │       │ │ ┌─────────────────────┐    │──────→│ │ Node egress rule │ │                       │ │
│ │                    │ │ └─────────────────┘ │       │ └───────────────┘               │                                  │ │       │ │ │ Node security group │    │       │ └──────────────────┘ │                       │ │
│ │                    │ │ ┌─────┐             │       │ ┌─────┐                         │                                  │ │       │ │ └─────────────────────┘    │       │ ┌─────┐              │                       │ │
│ │                    │ │ │ ... │             │       │ │ ... │                         │                                  │ │       │ └────────────────────────────┘       │ │ ... │              │                       │ │
│ │                    │ │ └─────┘             │       │ └─────┘                         │                                  │ │       │                                      │ └─────┘              │                       │ │
│ │                    │ └─────────────────────┘       └─────────────────────────────────┘                                  │ │       │                                      └──────────────────────┘                       │ │
│ │                    │ ┌────────────┐       ┌─────────────┐       ┌───────────────────────┐       ┌─────────────────────┐ │ │       │ ┌─────────────┐       ┌───────────────────┐                                         │ │
│ │                    │ │ Elastic IP │       │ NAT gateway │       │ Private default route │──────→│ Private route table │ │ │       │ │ EKS cluster │──────→│ IAM OIDC provider │                                         │ │
│ │                    │ │ optional   │──────→│ optional    │──────→│ optional              │       └─────────────────────┘ │ │       │ └─────────────┘       └───────────────────┘                                         │ │
│ │ ┌──────────┐       │ └────────────┘       └─────────────┘       └───────────────────────┘                               │ │       │ ┌──────────────────────────────┐       ┌──────────────────────────────────┐         │ │
│ │ │ CSOC VPC │──────→│ ┌──────────────────────┐       ┌──────────────────────────────────┐                                │ │──────→│ │ Cluster-creator access entry │──────→│ Cluster-admin policy association │         │ │
│ │ └──────────┘       │ │ Private subnets      │       │ Private route-table associations │                                │ │       │ └──────────────────────────────┘       └──────────────────────────────────┘         │ │
│ │                    │ │ ┌──────────────────┐ │       │ ┌───────────────┐                │                                │ │       │ ┌─────────────────────────────────┐       ┌────────────────────────────────┐        │ │
│ │                    │ │ │ Private subnet 1 │ │       │ │ Association 1 │                │                                │ │       │ │ Auto Mode custom-tag IAM policy │──────→│ Cluster-role policy attachment │        │ │
│ │                    │ │ └──────────────────┘ │       │ └───────────────┘                │                                │ │       │ └─────────────────────────────────┘       └────────────────────────────────┘        │ │
│ │                    │ │ ┌──────────────────┐ │       │ ┌───────────────┐                │                                │ │       │                                   ┌──────────────────────────────┐                  │ │
│ │                    │ │ │ Private subnet 2 │ │──────→│ │ Association 2 │                │                                │ │       │                                   │ Node IAM policy attachments  │                  │ │
│ │                    │ │ └──────────────────┘ │       │ └───────────────┘                │                                │ │       │                                   │ ┌────────────────────────┐   │                  │ │
│ │                    │ │ ┌─────┐              │       │ ┌─────┐                          │                                │ │       │ ┌─────────────────────────┐       │ │ Worker-node attachment │   │                  │ │
│ │                    │ │ │ ... │              │       │ │ ... │                          │                                │ │       │ │ Auto Mode node IAM role │──────→│ └────────────────────────┘   │                  │ │
│ │                    │ │ └─────┘              │       │ └─────┘                          │                                │ │       │ └─────────────────────────┘       │ ┌──────────────────────────┐ │                  │ │
│ │                    │ └──────────────────────┘       └──────────────────────────────────┘                                │ │       │                                   │ │ Registry-pull attachment │ │                  │ │
│ │                    │ ┌─────────────────────┐                                                                            │ │       │                                   │ └──────────────────────────┘ │                  │ │
│ │                    │ │ Default network ACL │                                                                            │ │       │                                   └──────────────────────────────┘                  │ │
│ │                    │ └─────────────────────┘                                                                            │ │       │                       ┌─────────────────────────────┐                               │ │
│ │                    │ ┌─────────────────────┐                                                                            │ │       │                       │ Primary security-group tags │                               │ │
│ │                    │ │ Default route table │                                                                            │ │       │                       │ ┌───────────────┐           │                               │ │
│ │                    │ └─────────────────────┘                                                                            │ │       │                       │ │ Blueprint tag │           │                               │ │
│ │                    │ ┌────────────────────────┐                                                                         │ │       │ ┌─────────────┐       │ └───────────────┘           │                               │ │
│ │                    │ │ Default security group │                                                                         │ │       │ │ EKS cluster │──────→│ ┌─────────────────┐         │                               │ │
│ │                    │ └────────────────────────┘                                                                         │ │       │ └─────────────┘       │ │ Environment tag │         │                               │ │
│ │                    └────────────────────────────────────────────────────────────────────────────────────────────────────┘ │       │                       │ └─────────────────┘         │                               │ │
│ └───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘       │                       │ ┌─────┐                     │                               │ │
│                                                                                                                                     │                       │ │ ... │                     │                               │ │
│                                                                                                                                     │                       │ └─────┘                     │                               │ │
│                                                                                                                                     │                       └─────────────────────────────┘                               │ │
│                                                                                                                                     │ ┌──────────────────────────────┐       ┌─────────────┐                              │ │
│                                                                                                                                     │ │ CloudWatch cluster log group │──────→│ EKS cluster │                              │ │
│                                                                                                                                     │ └──────────────────────────────┘       └─────────────┘                              │ │
│                                                                                                                                     └─────────────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

The module composes two upstream Terraform modules: `terraform-aws-vpc` first
creates the network foundation, then `terraform-aws-eks` deploys the cluster
into the private subnets and exposes identity and connectivity outputs for
downstream units.

## Contract

| Input | Default | Meaning |
| --- | --- | --- |
| `csoc_alias` | required | Base name for CSOC resources. |
| `vpc_cidr` | `10.0.0.0/16` | VPC address range. |
| `availability_zones` | `[]` | Explicit zones; empty selects two available standard zones. |
| `private_subnet_cidrs` | `[]` | Explicit private subnet ranges; empty derives them from the VPC range. |
| `public_subnet_cidrs` | `[]` | Explicit public subnet ranges; empty derives them from the VPC range. |
| `public_subnet_tags` | `{}` | Tags merged onto public subnets. |
| `private_subnet_tags` | `{}` | Tags merged onto private subnets. |
| `enable_nat_gateway` | `true` | Whether the VPC module creates NAT gateways. |
| `single_nat_gateway` | `true` | Whether all private subnets share one NAT gateway. |
| `kubernetes_version` | `1.35` | EKS Kubernetes version. |
| `cluster_endpoint_public_access` | `true` | Enables the public EKS API endpoint. |
| `enable_cluster_creator_admin_permissions` | `true` | Grants cluster-admin access to the cluster creator. |
| `cluster_compute_config` | Auto Mode with `general-purpose` and `system` pools | EKS compute configuration passed to the EKS module. |
| `environment` | `control-plane` | Environment tag value. |
| `tags` | `{}` | Additional common resource tags. |

| Output | Meaning |
| --- | --- |
| `cluster_name` | Created EKS cluster name. |
| `cluster_endpoint` | Sensitive EKS API endpoint. |
| `cluster_certificate_authority_data` | Sensitive base64-encoded cluster CA. |
| `cluster_oidc_issuer_url` | EKS OIDC issuer URL. |
| `oidc_provider_arn` | IAM OIDC provider ARN. |
| `vpc_id` | Created VPC ID. |
| `private_subnet_ids` | Created private subnet IDs. |
| `cluster_ready_token` | Ordering-only cluster/VPC token. |

[`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf) remain the
machine-enforced contract. Controller IAM and in-cluster units consume the
named outputs rather than reconstructing resource names.

The live owner is the `aws-csoc-cluster` unit in the
[`csoc-cluster-core` stack](../../../../terragrunt/live/aws/csoc-cluster-core/README.md), with
state key `csoc/aws-csoc-cluster/terraform.tfstate`.
