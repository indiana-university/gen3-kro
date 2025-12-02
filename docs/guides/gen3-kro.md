# Gen3 KRO Guide

Concise reference for the KRO ResourceGraphDefinitions (RGDs) and sample instances used to deploy Gen3 infrastructure.

---

## Layout

- RGDs live under `argocd/csoc-addons/rgds/<provider>/` and are synced by the `csoc-rgds-per-cloud` ApplicationSet (`argocd/bootstrap/csoc-rgds-per-cloud.yaml`).
- Multi-cloud composite graphs live in `argocd/csoc-addons/rgds/graph-of-graphs/` and are synced by `csoc-rgds-graph-of-graphs`.
- Reference instances (copy and adapt) live in `argocd/.instance-library-(for-reference)/<provider>/`.

## AWS RGD Inventory (synced via `argocd/csoc-addons/rgds/aws/kustomization.yaml`)

22 RGDs grouped by capability:
- Network: `aws-vpc`, `aws-vpc-public-subnet`, `aws-vpc-private-subnet`, `aws-vpc-db-subnet`
- IAM & access: `aws-irsa-role`, `aws-kms`, `aws-waf`
- Data & storage: `aws-s3bucket`, `aws-data-bucket`, `aws-secretsmanager`, `aws-efs`
- Messaging & events: `aws-sns`, `aws-sqs`, `aws-route53-public`, `aws-route53-private`
- Logging & audit: `aws-cloudwatch-logs`, `aws-cloudtrail`
- Datastores: `aws-rds`, `aws-aurora`, `aws-elasticache`, `aws-opensearch`
- Compute: `aws-eks`

All RGDs produce status fields (IDs, ARNs, endpoints) that can be referenced by other instances.

## Prerequisites

- Tools: `kubectl`, `argocd`, `kustomize` (v5+).
- Controllers: KRO plus ACK controllers for EC2, EKS, RDS, ElastiCache, IAM, KMS, OpenSearchService, Route53, S3, SecretsManager, SNS, SQS, EFS, CloudTrail, CloudWatchLogs, WAFv2. These are deployed by `argocd/bootstrap/csoc-controller-appset.yaml` and CRDs by `argocd/bootstrap/csoc-crds-appset.yaml` (sync wave precedes RGDs).

## Deploy RGDs (normal flow)

1) Ensure controller and CRD ApplicationSets are healthy:
```bash
kubectl get applicationset csoc-controller-appset -n argocd
kubectl get applicationset csoc-crds-appset -n argocd
```
2) Let `csoc-rgds-per-cloud` sync RGDs:
```bash
argocd app list -l app.kubernetes.io/name=rgds
kubectl get rgd -n kro-system
```

## Deploy RGDs (manual fallback)

```bash
# Apply all AWS RGDs
kubectl apply -k argocd/csoc-addons/rgds/aws
# Verify
kubectl get resourcegraphdefinitions -n kro-system
```

## Gen3 application manual sync checklist

ArgoCD deliberately pauses the `gen3-spoke-*-application` apps (sync wave `5`) until you manually trigger them. Before pressing **Sync**, verify the dependent infrastructure is Ready:

1. Confirm the AwsGenericCommonsAndBucket instance reports the required status fields:
  ```bash
  kubectl get awsgenericcommonsandbucket -n <spoke-namespace> \
    -o jsonpath='{.items[0].status}' | jq
  ```
  Ensure the output includes `eksClusterEndpoint`, `eksClusterCertificateAuthority`, and `auroraClusterEndpoint`.
2. Validate ArgoCD shows the spoke infrastructure app as `Synced` and `Healthy`:
  ```bash
  argocd app get <spoke>-infrastructure
  ```
3. Once the checks pass, manually sync the Gen3 application:
  ```bash
  argocd app sync gen3-spoke-<spoke>-application
  ```
  Monitor until status is `Synced`/`Healthy`. If sync fails, re-check infrastructure status fields before retrying.

## Create Instances (copy from reference library)

Example: base VPC, private subnet, and EKS that consume each other’s status:

```yaml
# vpc-instance.yaml
apiVersion: kro.run/v1alpha1
kind: AwsVpc
metadata:
  name: demo-vpc
  namespace: platform
spec:
  name: demo
  namespace: platform
  region: us-east-1
  environment: dev
  cidr:
    vpcCidr: 10.10.0.0/16
    publicSubnetCidr: 10.10.1.0/24
    privateSubnetCidr: 10.10.11.0/24
```

```yaml
# private-subnet-instance.yaml
apiVersion: kro.run/v1alpha1
kind: AwsPrivateSubnet
metadata:
  name: demo-private
  namespace: platform
spec:
  name: demo-private
  namespace: platform
  region: us-east-1
  vpcID: ${demo-vpc.status.vpcID}
  publicSubnetID: ${demo-vpc.status.publicSubnetID}
```

```yaml
# eks-instance.yaml
apiVersion: kro.run/v1alpha1
kind: AwsEKS
metadata:
  name: demo-eks
  namespace: platform
spec:
  name: demo-eks
  namespace: platform
  region: us-east-1
  vpcID: ${demo-vpc.status.vpcID}
  subnetIDs:
    - ${demo-private.status.subnetID}
  nodeGroupInstanceTypes: ["t3.medium"]
  nodeGroupDesiredSize: 2
  nodeGroupMinSize: 1
  nodeGroupMaxSize: 4
```

Apply with `kubectl apply -k <overlay>` or register an ArgoCD Application/ApplicationSet pointing at your overlay path.

## Troubleshooting

- RGDs missing: `kubectl get rgd -n kro-system`; if absent, sync `csoc-rgds-per-cloud` or `kubectl apply -k argocd/csoc-addons/rgds/aws`.
- Instance pending: `kubectl describe <kind> <name>` and check relevant ACK controller logs (e.g., `kubectl logs -n ack-system -l app.kubernetes.io/name=ack-ec2-controller`).
- CIDR or dependency errors: confirm referenced status fields resolve (`kubectl get <kind> <name> -o jsonpath='{.status}'`).
- ArgoCD sync issues: `argocd app get <app-name>` and review events; ensure controllers/CRDs are synced before RGDs.

---

Keep RGDs and instances in Git, avoid committing secrets, and prefer ExternalSecrets to surface provider credentials to workloads.
