# 09 — Future Refactoring Opportunities

Post-merge opportunities to reduce code duplication and improve structural
independence. None of these are required for the merge to function correctly.
Implement only when the benefit outweighs the complexity cost.

---

## 1. ACK Addons: Base + Overlay Extraction

**Problem**: `argocd/addons/csoc/addons.yaml` and `argocd/addons/local/addons.yaml`
share the same 9 ACK controller blocks (~85% identical). The only difference is
`ignoreDifferences` entries in the local file (needed for K8s Secret credential injection).

**Current duplication**: ~230 lines replicated across both files.

**Proposed solution**: Multi-source value files via the `addons_config_path` mechanism.

```
argocd/addons/
├── common/
│   └── ack-controllers.yaml        # NEW — base ACK versions + common settings
├── csoc/
│   └── addons.yaml                 # SLIM — only csoc-specific addons (external-secrets, cloudtrail, kro-csoc-rgs)
└── local/
    └── addons.yaml                 # SLIM — only ignoreDifferences overrides + kro-csoc-rgs
```

The `csoc-addons.yaml` bootstrap ApplicationSet would load both:
```yaml
valueFiles:
  - $values/argocd/addons/common/ack-controllers.yaml
  - $values/{{ .metadata.annotations.addons_config_path }}
```

**Benefit**: ~230 lines of duplication → ~30 lines per env-specific file.

**Risk / Complexity**:
- The `application-sets` Helm chart templates must support `ignoreDifferences`
  being settable from either the base OR the overlay values file. Verify the
  chart's templating supports deep-merge vs. last-wins override for this field.
- Requires testing that csoc-addons.yaml correctly stacks two valueFiles sources
  in the ArgoCD ApplicationSet `multi` source configuration.
- Medium complexity. Cannot be done without understanding the chart's templating.

**Verdict**: Worth doing after the merge is validated end-to-end.

---

## 2. Fleet ApplicationSet Templatization

**Problem**: `argocd/bootstrap/fleet-infra-instances.yaml` and
`argocd/bootstrap/local-infra-instances.yaml` share the same ApplicationSet
structure. Key differences:

| Field | fleet-infra-instances | local-infra-instances |
|-------|-----------------------|-----------------------|
| Selector | `fleet_member: fleet-spoke-infra` | `fleet_member: control-plane` |
| Annotation prefix | `fleet_repo_*` | `addons_repo_*` |
| Directory sources | 1 (infrastructure/ only) | 2 (infrastructure/ + tests/) |

**Proposed solution**: Parameterize as a Helm chart template in
`argocd/charts/application-sets/templates/`. Pass the two configs as values.

**Benefit**: Eliminates ~140 lines; fleet ApplicationSets become values-configurable.

**Risk / Complexity**:
- The `application-sets` chart already generates ApplicationSets. Adding two more
  parameterized templates is incremental.
- The annotation prefix difference (`fleet_repo_*` vs `addons_repo_*`) means the
  template must use a configurable prefix, which adds template complexity.
- **Low benefit** given the files are only ~70 lines each and rarely change. The
  divergence in source count (1 vs 2) also makes a clean template harder.

**Verdict**: Low priority. The files are simple and stable. Skip unless the
cluster fleet grows and a third variant is needed.

---

## 3. Shared Script Logging Library

**Problem**: `kind-local-test.sh`, `kro-status-report.sh`, and `container-init.sh`
each embed ~30–50 lines of identical TTY-aware logging functions inline. The
current approach (inline embedding, no shared library) was an explicit design
choice during the merge to avoid bringing over gen3-dev's `lib-logging.sh`.

**Proposed solution**: Create `scripts/lib-logging.sh` as a shared library,
which each script sources:

```bash
# In each script:
# shellcheck source=scripts/lib-logging.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib-logging.sh"
```

**Benefit**:
- ~40-line reduction per script (net ~120 lines removed across 3 scripts).
- Single point of change for log formatting improvements.
- `shellcheck source=` directive preserves static analysis.

**Risk / Complexity**:
- Scripts must be run from the repo root OR handle `$(dirname "$0")` correctly.
- Scripts called from a container post-start command need the path to resolve.
- Low risk — this is a pure refactor with no behavior change.

**Verdict**: High confidence, low risk. Good candidate for a follow-up PR.

---

## 4. Summary Table

| # | Opportunity | Lines Saved | Complexity | Priority |
|---|-------------|-------------|------------|----------|
| 1 | ACK addons base+overlay | ~200 | Medium | After e2e validation |
| 2 | Fleet ApplicationSet template | ~80 | Medium | Low (skip unless 3rd variant needed) |
| 3 | Shared logging library (`lib-logging.sh`) | ~120 | Low | High — good first follow-up |
