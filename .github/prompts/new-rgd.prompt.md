---
name: new-rgd
description: 'Scaffold a new KRO ResourceGraphDefinition for gen3-kro'
agent: agent
tools: ['search/codebase', 'edit/editFiles', 'search']
argument-hint: 'Component name (e.g. "database2", "messaging2", "waf1")'
---

# Scaffold a New KRO ResourceGraphDefinition

## Inputs

- **Component name**: ${input:componentName:e.g. database2}
- **Description**: ${input:description:Brief description of what this RGD manages}
- **Depends on**: ${input:dependsOn:Comma-separated bridge ConfigMap names, or "none"}

## Steps

1. Determine the versioned name:
   - `metadata.name`: lowercase, no hyphens (e.g., `awsgen3${input:componentName}`)
   - `kind`: CamelCase (e.g., `AwsGen3${input:componentName}`)
   - Filename: `argocd/csoc-eks/charts/aws-rgds-v1/templates/awsgen3${input:componentName}-rg.yaml`

2. Read existing RGDs for patterns — start with the closest match:
   ```bash
   ls argocd/csoc-eks/charts/aws-rgds-v1/templates/
   ```

3. Scaffold the RGD with:
   - Standard schema fields: `region`, `adoptionPolicy`, `deletionPolicy`, `namespace`, `name`
   - ACK annotations on every resource template
   - `readyWhen` with both ARN and ACK.ResourceSynced checks
   - `externalRef` blocks for each upstream bridge (from `dependsOn`)
   - Output bridge ConfigMap named `<component>Bridge`

4. Create a test instance in `argocd/local-kind/test/infrastructure/`:
   ```yaml
   apiVersion: kro.run/v1alpha1
   kind: AwsGen3${input:componentName}
   metadata:
     name: gen3
     namespace: spoke1
     annotations:
       argocd.argoproj.io/sync-wave: "30"
       argocd.argoproj.io/sync-options: ServerSideApply=true
   spec:
     namespace: spoke1
   ```

5. Verify the RGD is syntactically valid YAML with no bare `${}` expressions.

6. Reference `.github/instructions/kro-rgd.instructions.md` for all conventions.
