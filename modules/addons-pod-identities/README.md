# EKS Pod Identities Module# EKS Pod Identities Module



This module creates and manages EKS Pod Identity associations for Kubernetes addons. It provides a centralized way to configure IAM roles for pods running in EKS clusters.This module manages all EKS Pod Identity configurations for various Kubernetes addons and controllers.



## Features## Features



- **21 Pod Identity Configurations** - Support for all major Kubernetes addons- Consolidates all pod identity configurations in one place

- **Conditional Creation** - Enable/disable each addon independently- Supports EBS CSI Driver

- **Flexible Configuration** - Customizable namespaces, service accounts, and policies- Supports External Secrets Operator

- **Comprehensive Outputs** - Individual and consolidated role ARN outputs- Supports AWS Load Balancer Controller

- **Best Practices** - Uses official AWS EKS Pod Identity module- Supports ArgoCD Hub

- Supports ACK (AWS Controllers for Kubernetes) services

## Supported Addons

## Inputs

### Storage

- AWS EBS CSI Driver### Common Variables

- AWS EFS CSI Driver

- AWS FSx for Lustre CSI Driver| Name | Description | Type | Default | Required |

- Mountpoint S3 CSI Driver|------|-------------|------|---------|----------|

| cluster_name | Name of the EKS cluster | string | n/a | yes |

### Networking| tags | Tags to apply to all resources | map(string) | {} | no |

- AWS Load Balancer Controller

- AWS Load Balancer Controller (Target Group Binding Only)### EBS CSI Variables

- AWS Gateway Controller

- AWS VPC CNI (IPv4)| Name | Description | Type | Default | Required |

- AWS VPC CNI (IPv6)|------|-------------|------|---------|----------|

- External DNS| enable_aws_ebs_csi | Enable AWS EBS CSI driver pod identity | bool | false | no |

| ebs_csi_kms_arns | KMS key ARNs for EBS CSI driver | list(string) | ["arn:aws:kms:*:*:key/*"] | no |

### Service Mesh| ebs_csi_namespace | Kubernetes namespace for EBS CSI driver | string | "kube-system" | no |

- AWS AppMesh Controller| ebs_csi_service_account | Kubernetes service account for EBS CSI driver | string | "ebs-csi-controller-sa" | no |

- AWS AppMesh Envoy Proxy

### External Secrets Variables

### Security & Secrets

- External Secrets| Name | Description | Type | Default | Required |

- Cert Manager|------|-------------|------|---------|----------|

- AWS Private CA Issuer| enable_external_secrets | Enable External Secrets pod identity | bool | false | no |

| external_secrets_kms_key_arns | KMS key ARNs for External Secrets | list(string) | [] | no |

### Observability| external_secrets_secrets_manager_arns | Secrets Manager ARNs for External Secrets | list(string) | [] | no |

- AWS CloudWatch Observability| external_secrets_ssm_parameter_arns | SSM Parameter ARNs for External Secrets | list(string) | [] | no |

- Amazon Managed Service for Prometheus| external_secrets_create_permission | Allow External Secrets to create secrets | bool | false | no |

| external_secrets_attach_custom_policy | Attach custom policy to External Secrets role | bool | false | no |

### GitOps & CI/CD| external_secrets_policy_statements | Custom policy statements for External Secrets | any | [] | no |

- ArgoCD Hub| external_secrets_namespace | Kubernetes namespace for External Secrets | string | "external-secrets" | no |

| external_secrets_service_account | Kubernetes service account for External Secrets | string | "external-secrets" | no |

### Operations

- Cluster Autoscaler### AWS Load Balancer Controller Variables

- AWS Node Termination Handler

- Velero| Name | Description | Type | Default | Required |

|------|-------------|------|---------|----------|

## Usage| enable_aws_load_balancer_controller | Enable AWS Load Balancer Controller pod identity | bool | false | no |

| aws_load_balancer_controller_namespace | Kubernetes namespace for AWS Load Balancer Controller | string | "kube-system" | no |

### Basic Example| aws_load_balancer_controller_service_account | Kubernetes service account for AWS Load Balancer Controller | string | "aws-load-balancer-controller" | no |



```hcl### ArgoCD Variables

module "eks_pod_identities" {

  source = "../../modules/eks-pod-identities"| Name | Description | Type | Default | Required |

|------|-------------|------|---------|----------|

  cluster_name = "my-cluster"| enable_argocd | Enable ArgoCD pod identity | bool | false | no |

| argocd_namespace | Kubernetes namespace for ArgoCD | string | "argocd" | no |

  # Enable EBS CSI Driver

  enable_aws_ebs_csi = true### ACK Variables



  # Enable External Secrets| Name | Description | Type | Default | Required |

  enable_external_secrets = true|------|-------------|------|---------|----------|

  external_secrets_kms_key_arns = [| ack_services_config | Configuration for ACK services pod identity associations | map(any) | {} | no |

    "arn:aws:kms:us-east-1:123456789012:key/*"| ack_hub_roles | Map of ACK Hub IAM roles (should contain arn for each service) | map(any) | {} | no |

  ]

## Outputs

  # Enable AWS Load Balancer Controller

  enable_aws_load_balancer_controller = true| Name | Description |

|------|-------------|

  tags = {| aws_ebs_csi_role_arn | IAM Role ARN for AWS EBS CSI driver |

    Environment = "production"| external_secrets_role_arn | IAM Role ARN for External Secrets |

    ManagedBy   = "terraform"| aws_lb_controller_role_arn | IAM Role ARN for AWS Load Balancer Controller |

  }| argocd_hub_role_arn | IAM Role ARN for ArgoCD Hub |

}| ack_pod_identity_associations | ACK Pod Identity Associations |

```| pod_identity_roles | All Pod Identity IAM Role ARNs |



## Testing## Usage



To test the module locally:```hcl

module "eks_pod_identities" {

```bash  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/eks-pod-identities?ref=main"

cd modules/eks-pod-identities

terraform init  cluster_name = module.eks_cluster.cluster_name

terraform validate

terraform plan -var-file=test.tfvars  # Enable EBS CSI

```  enable_aws_ebs_csi = true



## Requirements  # Enable External Secrets

  enable_external_secrets                   = true

| Name | Version |  external_secrets_kms_key_arns             = ["arn:aws:kms:us-east-1:*:key/my-cluster/*"]

|------|---------|  external_secrets_secrets_manager_arns     = ["arn:aws:secretsmanager:us-east-1:*:secret:my-cluster/*"]

| terraform | >= 1.3 |  external_secrets_ssm_parameter_arns       = ["arn:aws:ssm:us-east-1:*:parameter/my-cluster/*"]

| aws | >= 5.0 |

  # Enable AWS Load Balancer Controller

## License  enable_aws_load_balancer_controller = true



This module is part of the gen3-kro project.  # Enable ArgoCD

  enable_argocd = true

  # ACK Services
  ack_services_config = {
    iam = {
      namespace       = "ack-system"
      service_account = "ack-iam-controller"
    }
  }
  ack_hub_roles = module.eks_hub.ack_hub_roles

  tags = {
    Environment = "production"
    Project     = "gen3-kro"
  }
}
```

## Dependencies

This module depends on:
- EKS Cluster module (requires cluster_name)
- EKS Hub module (requires ack_hub_roles for ACK services)
