# Terraform catalog

The catalog separates resource implementation from environment orchestration:

```text
Stage 1 - live stack   Stage 2 - catalog unit   Stage 3 - Terraform module   Stage 4 - provider API

live Terragrunt stack → catalog unit → Terraform module → provider API
```

- [`modules`](modules/README.md) define reusable resources and their input/output
  contracts.
- [`units`](units/README.md) add remote state, providers, dependency handoff, and
  stack-compatible outputs.

Modules do not read `config/shared.auto.tfvars.json` and should not know live
state keys. Units do not contain environment values; a live stack supplies them
through its `values` object. This keeps module testing independent of an
environment while keeping orchestration and state ownership explicit.
