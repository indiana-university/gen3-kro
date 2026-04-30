# Local Kind Test Instances

KRO instance YAML files for the local Kind CSOC cluster. Managed by the
`fleet-instances` ApplicationSet via `fleet_instances_path: "local-kind/test"`.

## Layout

```
test/
├── infrastructure/     # Production infra-tier instances (real AWS): Network, DNS, Storage,
│                       #   Compute, Database, Search, AppIAM, Advanced, Messaging
├── cluster-resources/  # ClusterResources1 instance (spoke EKS registration)
├── applications/       # Helm1 instance (gen3-helm deployment)
└── tests/              # KRO capability test instances (Tests 1-9)
```

Infrastructure and test instances are commented out by default — uncomment to activate.
See `scripts/kind-csoc.sh` for credential injection and cluster management.
