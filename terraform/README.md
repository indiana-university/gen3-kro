# Terraform Source

Reusable infrastructure modules and opinionated “combination” stacks that Terragrunt consumes.

- `modules/argocd/`: Installs ArgoCD via Helm, registers cluster secrets, and bootstraps the App-of-Apps chart.
- `modules/vpc/`: Creates hub/spoke VPC networking (public/private subnets, NAT) with tags tuned for EKS.
- `modules/eks-cluster/`: Provisions the EKS control plane and optional managed node pools.
- `modules/pod-identity/`: Generates IAM roles/service accounts for pod identity across ACK controllers and addons.
- `modules/ack-spoke-role/`: Issues cross-account IAM roles that spokes assume when calling hub ACK controllers.
- `modules/cross-account-policy/`: Grants hub pod identity roles permission to operate on spoke accounts.
- `modules/iam-policy/`: Helper for assembling inline IAM policies from repo templates or remote Git targets.
- `combinations/hub/`: Orchestrated stack wiring VPC, EKS, pod identity, cross-account policies, and optional ArgoCD installation.
  - `applicationsets.yaml`, `argocd-initial-values.yaml`: Values injected into the ArgoCD module by Terragrunt.
  - `.terraform.lock.hcl`, `.terraform/`: Provider lock and init cache (generated).
- `combinations/spoke-iam/`: Bundles pod identity and cross-account roles for spoke clusters.
- `.terraform-docs.yml`: Configuration used when regenerating Terraform module documentation.

Terragrunt wrappers under `live/` reference these modules via `terraform.source`.

