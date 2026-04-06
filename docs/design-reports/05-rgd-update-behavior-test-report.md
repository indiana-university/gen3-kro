# 05 — RGD Update Behavior Test Report

**Date:** 2026-03-11
**Cluster:** Kind local-aws-dev (gen3-kro)
**KRO Version:** 0.8.5
**Test RGD:** `kro-includewhen-test` (KroIncludeWhenTest)
**Method:** Git push → ArgoCD auto-sync → KRO reconcile (no manual `kubectl apply`)

---

## Summary

| Scenario | Manual Sync Required? | KRO Auto-Reconciles? | Result |
|----------|----------------------|---------------------|--------|
| Add resource (no schema change) | No | Yes | New resources created in all instances within ~15s |
| Remove resource (no schema change) | No | Yes | Removed resources garbage-collected from all instances |
| Add schema field + resource | No | Yes | CRD updated, existing instances pick up default value |
| Remove schema field (breaking) | N/A — **blocked** | **No — RGD goes Inactive** | Breaking change protection triggers |

---

## Test Details

### Test 1: Add Resource Without Schema Change

**Change:** Added an unconditional ConfigMap (`alwaysOnMeta`) that uses only existing schema fields (`name`, `namespace`, `environment`).

**Procedure:**
1. Edit RGD YAML → `git push`
2. `argocd app get --hard-refresh` (or wait for 3-min poll)
3. ArgoCD detects OutOfSync → auto-syncs within seconds

**Result:**
- ArgoCD synced the RGD automatically (auto-sync + selfHeal enabled)
- KRO detected the new resource definition in the graph
- `includewhen-minimal-always-on-meta` and `includewhen-full-always-on-meta` ConfigMaps created in both instance namespaces
- Both instances remained ACTIVE/Ready — **zero downtime**
- Total time from push to resource creation: **~15 seconds** (after ArgoCD detected the change)

### Test 2: Remove Resource Without Schema Change

**Change:** Removed the `alwaysOnMeta` ConfigMap added in Test 1.

**Procedure:** Same as Test 1 (git push → ArgoCD auto-sync)

**Result:**
- ArgoCD synced the updated RGD
- KRO garbage-collected the removed ConfigMaps from both namespaces
- Both instances remained ACTIVE/Ready — **zero downtime**
- Original resources unaffected

### Test 3: Add Schema Field + Resource (Non-Breaking Change)

**Change:** Added a new spec field (`teamLabel: string | default="platform"`), a new status field (`teamConfig`), and a new ConfigMap resource (`teamConfig`) that uses the new field.

**Procedure:** Same git push → ArgoCD auto-sync flow

**Result:**
- KRO updated the CRD (`kroincludewhentests.kro.run`) adding the `teamLabel` property with `{"default":"platform","type":"string"}`
- Existing instances (which don't specify `teamLabel`) automatically received the default value `"platform"`
- New `team-config` ConfigMaps created in both namespaces with `team: platform`
- Both instances remained ACTIVE/Ready — **zero downtime**
- New status field `teamConfig` populated on both instances

**Key insight:** Adding schema fields with defaults is a **non-breaking change** that KRO handles seamlessly.

### Test 4: Remove Schema Field (Breaking Change)

**Change:** Reverted Test 3 — removed `teamLabel` from spec, `teamConfig` from status, and the `teamConfig` resource.

**Procedure:** Same git push → ArgoCD auto-sync flow

**Result:**
- ArgoCD synced the RGD successfully
- **KRO rejected the CRD update** with:
  ```
  cannot update CRD kroincludewhentests.kro.run: breaking changes detected:
  Property teamLabel was removed; Property teamConfig was removed
  ```
- RGD state changed to **Inactive** (condition `KindReady: Failed`)
- Existing instances continued running (ACTIVE/True) — resources remained in the cluster
- **However**, instance deletion gets stuck in `DELETING` state because the Inactive RGD's dynamic controller is not processing finalizers

#### Recovery Procedure for Breaking Schema Changes

When a schema field removal puts the RGD into Inactive state:

1. **Remove all instances first** (they may need finalizer patching):
   ```bash
   # Remove finalizer from stuck instances
   kubectl patch <kind> <name> -n <ns> \
     -p '{"metadata":{"finalizers":null}}' --type=merge
   # Then delete
   kubectl delete <kind> <name> -n <ns>
   ```

2. **Delete the CRD** (KRO will recreate it from the current RGD):
   ```bash
   kubectl delete crd kroincludewhentests.kro.run
   ```

3. **Wait ~10 seconds** — KRO detects the missing CRD and recreates it with the updated schema. RGD returns to **Active**.

4. **Sync the instance app** to recreate instances:
   ```bash
   argocd app sync <instance-app> --force --prune
   ```

5. **Verify** instances are ACTIVE/Ready with correct resources.

---

## Confirmed Procedure

### For Non-Breaking Changes (add fields/resources, modify templates)

```
Edit RGD YAML → git push → done
```

ArgoCD auto-syncs the RGD. KRO reconciles all instances automatically.
No manual intervention. Zero downtime.

### For Breaking Changes (remove/rename schema fields)

```
Edit RGD YAML → git push → ArgoCD syncs → RGD goes Inactive →
  manual recovery required (delete instances → delete CRD → re-sync instances)
```

**Recommended approach:** Avoid breaking changes. Instead:
- **Deprecate** fields by keeping them in the schema with comments
- **Version** the RGD (e.g., `kro-includewhen-test-v2`) with new schema
- **Migrate** instances to the new version, then delete the old RGD

---

## ArgoCD Configuration (Verified)

| App | Auto-Sync | Prune | Self-Heal |
|-----|-----------|-------|-----------|
| `kro-local-rgs-local-aws-dev` (RGDs) | Yes | Yes | Yes |
| `local-aws-dev-infra-instance` (instances) | Yes | Yes | No |

Both apps use `allowEmpty: true` for safe sync during initial bootstrap.

---

## Key Findings

1. **KRO is a true reconciler** — it watches RGD changes and automatically reconciles all instances. No manual `kubectl apply` of instances is needed.

2. **ArgoCD + KRO is fully GitOps** — push to git and everything flows:
   `git push` → ArgoCD detects → syncs RGD → KRO reconciles instances → resources created/updated/deleted

3. **Breaking change protection** — KRO prevents CRD field removal to protect running instances. This is a safety feature, not a bug.

4. **Default values propagate** — adding a schema field with a default immediately applies to all existing instances without instance YAML changes.

5. **Finalizer awareness** — when the RGD is Inactive, instance deletion requires manual finalizer removal. Plan for this in operational runbooks.
