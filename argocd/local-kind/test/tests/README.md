# KRO Capability Test Instances

KRO test instance YAMLs for validating KRO features against the local Kind cluster.
Managed by the `fleet-instances` ApplicationSet (sync-wave 30).

- Tests 1-5: pure K8s (ConfigMap-based, no AWS credentials needed)
- Tests 6-8: real AWS (ACK EC2, require valid credentials and active ACK controllers)

RGDs: `argocd/charts/resource-groups/templates/krotest*-rg.yaml`
