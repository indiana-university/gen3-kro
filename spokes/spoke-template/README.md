# Spoke Template

This directory contains the template for creating new spoke clusters.

## Structure

```
spoke-template/
├── infrastructure/         # Infrastructure RGDs (EKS cluster, VPC, etc.)
│   ├── base/              # Base RGD instances
│   └── overlays/          # Environment-specific overlays
├── applications/          # Applications to deploy to the spoke
│   └── <app-name>/
│       ├── base/
│       └── overlays/
└── argocd/               # ArgoCD Applications/ApplicationSets
    ├── base/
    └── overlays/
```

## Creating a New Spoke

1. Copy this template:
   ```bash
   cp -r spokes/spoke-template spokes/my-spoke
   ```

2. Update the infrastructure RGD instance in `infrastructure/base/eks-cluster-instance.yaml`

3. Create a spoke config in `config/spokes/my-spoke.yaml`

4. Commit and push - ArgoCD will sync automatically

## Customization

- Edit `infrastructure/base/eks-cluster-instance.yaml` to customize cluster settings
- Add applications in the `applications/` directory
- Customize per-environment settings in overlays
