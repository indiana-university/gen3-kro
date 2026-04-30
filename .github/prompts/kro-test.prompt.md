---
name: kro-test
description: 'Scaffold a new KRO capability test (RGD + instance pair)'
agent: agent
tools: ['search/codebase', 'edit/editFiles', 'search']
argument-hint: 'Test number and feature being tested (e.g. "9 cross-namespace-refs")'
---

# Scaffold KRO Capability Test

## Inputs

- **Test number**: ${input:testNum:e.g. 9}
- **Feature**: ${input:feature:e.g. cross-namespace-refs}
- **Uses real AWS?**: ${input:usesAWS:yes or no}

## Steps

1. Check existing tests for the next available number:
   ```bash
   ls argocd/charts/resource-groups/templates/ | grep krotest
   ```

2. Create the RGD at:
   `argocd/charts/resource-groups/templates/krotest${input:testNum}-${input:feature}-rg.yaml`

3. Create test instances in:
   - `argocd/local-kind/test/tests/` (if `usesAWS: no`)
   - `argocd/local-kind/test/infrastructure/` (if `usesAWS: yes`)

4. Instance naming convention: `kro-${input:feature}-<variant>` (e.g., `kro-cross-namespace-basic`)

5. After creating the files, add an entry to the KRO Capability Tests table in
   `.github/copilot-instructions.md`.

6. Reference the existing test files (krotest01 through krotest08) for patterns.
