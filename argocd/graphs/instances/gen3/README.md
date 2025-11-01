# Gen3 Instance Templates

Instance templates for Gen3 infrastructure using Kustomize.

## Quick Start

```bash
# Preview
kubectl kustomize argocd/graphs/instances/gen3/

# Deploy
kubectl apply -k argocd/graphs/instances/gen3/
```

## Prerequisites

- RGDs deployed: `kubectl get rgd -n kro-system | grep gen3`
- ACK controllers running
- AWS credentials configured

## Customization

### Environment Overlays

```bash
mkdir -p overlays/{dev,staging,prod}

cat > overlays/dev/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: dev
resources:
  - ../../base
patches:
  - target:
      kind: Gen3Vpc
    patch: |-
      - op: replace
        path: /spec/cidr/vpcCidr
        value: "10.0.0.0/16"
EOF
```

### ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gen3-instances
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <your-repo>
    path: argocd/graphs/instances/gen3
  destination:
    namespace: default
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
```

## Example Instances

### S3 Bucket
```yaml
apiVersion: kro.run/v1alpha1
kind: Gen3S3Bucket
metadata:
  name: gen3-data
spec:
  name: gen3-data-12345
  region: us-east-1
```

### RDS Database
```yaml
apiVersion: kro.run/v1alpha1
kind: Gen3RDS
metadata:
  name: gen3-postgres
spec:
  name: gen3-postgres
  region: us-east-1
  vpcID: ${gen3-vpc-dev.status.vpcID}
  subnetIDs:
    - ${gen3-vpc-dev.status.privateSubnet1ID}
    - ${gen3-vpc-dev.status.privateSubnet2ID}
  databaseName: gen3
```

## Verification

```bash
# List instances
kubectl get gen3vpc,gen3rds,gen3s3bucket

# Check status
kubectl get gen3vpc gen3-vpc-dev -o jsonpath='{.status}'
```

## Documentation

Complete guide: [Gen3 KRO Guide](../../../docs/guides/gen3-kro.md)
