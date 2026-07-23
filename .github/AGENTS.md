# AGENTS.md

## Scope

This directory contains optional GitHub Copilot agents, prompts, hooks, skills,
and compatibility instructions. Canonical project rules live in the nearest
repository `AGENTS.md`; these files must summarize or operationalize those
rules without overriding them.

## Directory Contracts

- `copilot-instructions.md` is the repository-wide compatibility summary. Keep
  it concise and point to canonical scoped instruction files.
- `instructions/*.instructions.md` require YAML frontmatter with an accurate
  `description` and `applyTo` glob. Their body should name the canonical
  `AGENTS.md`, restate only essential rules, and not create a competing policy.
- `agents/*.agent.md` require valid frontmatter (`name`, `description`, `tools`,
  and supported `model`) followed by a bounded role, safe operating principles,
  current resource names, and evidence-based workflows. Do not grant a tool the
  role does not need.
- `prompts/*.prompt.md` require valid prompt frontmatter, explicit inputs,
  placeholder-safe examples, and a deterministic output contract. Prompts may
  diagnose or scaffold, but must not silently apply or destroy infrastructure.
- `skills/*/SKILL.md` require valid skill frontmatter and a trigger description
  narrow enough to avoid accidental use. Commands must follow current paths,
  namespaces, resource kinds, and repository safety rules.
- `hooks/<name>/hooks.json` defines the event, matcher, command, environment,
  working directory, and timeout. Keep the adjacent shell implementation in
  sync. Hook scripts consume untrusted command/diff input: quote it, avoid
  evaluation, bound runtime, and provide an explicit warn/block mode.

## Accuracy and Synchronization

- Search the implementation before changing example commands. Agent metadata
  is documentation, not evidence that a named resource, namespace, or script
  still exists.
- When canonical rules change, update the matching compatibility instruction,
  agent, prompt, or skill in the same change if it repeats that rule.
- Do not add real identifiers or credentials to examples. Use placeholders and
  exclude ignored local/generated directories from scanners.
- No workflow directory currently defines CI. If workflows are introduced,
  use pinned actions, minimal token permissions, no pull-request secret
  exposure, and the same narrow validation commands documented by the subtree.

## Validation

```bash
jq empty .github/hooks/*/hooks.json
bash -n .github/hooks/*/*.sh
git diff --check -- .github
```

Also verify every frontmatter block parses, every `applyTo` glob covers the
intended files, referenced scripts exist, and hook command files remain
executable. Do not run blocking/destructive hook examples merely to validate
documentation.

## Safety

Never embed secrets, real account IDs, account-bearing ARNs, tokens, private
keys, kubeconfigs, state, plans, generated stack content, outputs, or local
credential material in agents, prompts, skills, hook fixtures, or examples.

## Architecture Diagram Semantics

- Nesting means ownership or containment; it never means dependency.
- A solid connector between resource boxes means the destination consumes data,
  configuration, or a reference from the source. Draw fan-out and fan-in with
  explicit tee branches, keep arrowheads touching consumers, and leave resources
  unconnected when no such flow exists.
- Do not turn `depends_on`, Terragrunt ordering, Argo CD sync waves, an opaque
  ordering token, or observed apply sequence into a resource-data connector.
  Show ordering-only information with one detached guide such as `Deployment
  order only (not resource data): earlier -> later`, and arrange the diagram in
  that general direction.
- State connector meanings in a legend or adjacent text. Unit, module, or stack
  orchestration connectors may represent ordering when labeled; a connector
  must not silently switch between containment, data flow, and ordering.
