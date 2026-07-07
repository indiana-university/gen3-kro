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
   ls argocd/csoc/kro/aws-rgds/test/ | grep krotest
   ```

2. Create the RGD at:
   `argocd/csoc/kro/aws-rgds/test/krotest${input:testNum}-${input:feature}-rg.yaml`

3. Create local test instances in an appropriate spoke overlay under `argocd/spokes/`.

4. Instance naming convention: `kro-${input:feature}-<variant>` (e.g., `kro-cross-namespace-basic`)

5. After creating the files, add an entry to the KRO Capability Tests table in
   `argocd/csoc/kro/aws-rgds/test/README.md`.

6. Reference the existing test files and `argocd/csoc/kro/AGENTS.md` for patterns.
