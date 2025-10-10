# ArgoCD Configuration Structure

## Overview
- `hub/` - Hub cluster bootstrap and configuration
- `teams/` - Team-specific configurations
- `spokes/` - Spoke instance configurations per tenant and Gen3 URL

## Structure

```
argo/
├── hub/
│   ├── bootstrap/         # Hub bootstrap applications
│   ├── values/            # Default and override values
│   ├── charts/            # Helm charts (ACK, addons)
│   └── graphs/            # KRO Resource Graph Definitions
├── teams/                 # Team configurations
└── spokes/                # Spoke instance deployments
    └── {tenant}/
        └── {gen3_url}/
```

## Deployment Flow

1. **Hub Bootstrap** (`hub/bootstrap/`) - Core infrastructure
2. **RGDs** (`hub/graphs/aws/`) - Resource Graph Definitions
3. **Spokes** (`spokes/{tenant}/{gen3_url}/`) - Tenant instances
