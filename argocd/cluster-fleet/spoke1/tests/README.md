# KRO Capability Test Instances
#
# Place KRO test instance YAMLs here. ArgoCD's fleet-instances ApplicationSet
# reads this directory as a source (sync-wave 30).
#
# Tests 1-5: pure K8s (no AWS needed, ConfigMap-based)
# Tests 6-8: real AWS (ACK EC2, require valid credentials)
#
# See argocd/charts/resource-groups/templates/krotest*-rg.yaml for RGDs.
