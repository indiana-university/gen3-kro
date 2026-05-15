# KRO Capability Tests

These ResourceGraphDefinitions are synced by `csoc-kro`. Installing the RGDs
only creates CRDs; test resources are created only when you create instances.

Tests 6 and 7 create real ACK EC2 resources if instances are created from their
CRDs. Tests 9 and 10 use only Kubernetes resources to validate ACK compute
shaping and excluded-resource bridge patterns without AWS resources.
