# 08 — Validation Checklist

## Documentation completion — ✅ Done

- [x] `.gitignore` does NOT ignore `.github/**`
- [x] `config/local.env` is gitignored
- [ ] All scripts pass `shellcheck` (no errors)
- [ ] `devcontainer.json` builds and starts (EKS workflow)
- [x] `.github/copilot-instructions.md` created
- [x] All 5 `.github/instructions/*.instructions.md` files created
- [x] `docs/local-csoc-guide.md` created
- [x] `docs/architecture.md` updated with local CSOC section
- [x] `docs/deployment-guide.md` updated (host-based local CSOC)
- [x] `README.md` has dual-workflow quick-start
- [x] `CONTRIBUTING.md` has local CSOC section
- [x] No gen3-dev references remain in the new files

## End-to-end local CSOC smoke test

```bash
bash scripts/kind-local-test.sh create
bash scripts/kind-local-test.sh install
bash scripts/kind-local-test.sh inject-creds
bash scripts/kind-local-test.sh connect
bash scripts/kind-local-test.sh test
bash scripts/kro-status-report.sh
bash scripts/kind-local-test.sh destroy
```

- [ ] Kind cluster `gen3-local` creates and kubectl connects
- [ ] ArgoCD + bootstrap ApplicationSets deploy
- [ ] ACK controllers receive credentials and start
- [ ] `kro-csoc-rgs` Application Healthy/Synced
- [ ] All 18 RGDs Active (9 production + 9 test)
- [ ] Tests 1–5 (ConfigMap-only) produce expected data
- [ ] Tests 6/7a/7b create and cross-reference real AWS SecurityGroups
- [ ] Test 8 chained orValue both variants correct
- [ ] Status report generates without errors
- [ ] Kind cluster destroys cleanly; AWS test resources cleaned up


> **Updated**: Reflects revised Phase 5 (no Kind in container, no devcontainer-local.json).
> Dockerfile validation items removed. Local CSOC runs on host.

---

## 1. Pre-Merge Checks

### 1.1 File Integrity

- [x] All 9 test RGD files in `charts/resource-groups/templates/` ✅
- [x] All 9 production RGD files unchanged ✅
- [x] `local-aws-dev/` directory tree has all 19 files ✅
- [ ] No secrets, account IDs, or credentials in any committed file
- [ ] `.gitignore` does NOT ignore `.github/**` (blocked Copilot instructions)
- [ ] `config/local.env` is gitignored

### 1.2 Rename Consistency

- [x] `kro-eks-rgs` does NOT appear anywhere in the repo ✅
- [x] `kro-local-rgs` does NOT appear anywhere in the repo ✅
- [x] `kro-csoc-rgs` appears in `csoc/addons.yaml` and `local/addons.yaml` ✅
- [x] Terraform cluster secret labels use `enable_kro_csoc_rgs` ✅

### 1.3 Script Validation

- [x] `kind-local-test.sh` references `gen3-kro` repo URL ✅
- [x] `kro-status-report.sh` references `addons/local/addons.yaml` ✅
- [ ] All scripts pass `shellcheck` (no errors)

### 1.4 DevContainer

- [ ] `devcontainer.json` builds and starts (EKS workflow)
- [x] `devcontainer.json` has `chat.instructionsFilesLocations` ✅
- [ ] No `devcontainer-local.json` exists (confirmed eliminated)

### 1.5 Documentation (Phase 6 — ✅ complete)

- [x] `.github/copilot-instructions.md` created
- [x] All 5 `.github/instructions/*.instructions.md` files created
- [x] `docs/local-csoc-guide.md` created
- [x] `docs/architecture.md` updated with local CSOC section
- [x] `docs/deployment-guide.md` updated (host-based local CSOC)
- [x] `README.md` has dual-workflow quick-start
- [x] `CONTRIBUTING.md` has local CSOC section

---

## 2. EKS CSOC Validation (Post Phase 1 — verify no regression)

### 2.1 ArgoCD Health

- [ ] ArgoCD accessible via port-forward
- [ ] `argocd app list` shows all applications
- [ ] No applications in `Unknown` or `Error` state
- [ ] `kro-csoc-rgs-*` applications exist (replaced `kro-eks-rgs-*`)

### 2.2 KRO Controller

- [ ] KRO controller pod Running in `kro` namespace
- [ ] All RGDs Active: `kubectl get resourcegraphdefinitions -A`

### 2.3 ACK Controllers

- [ ] All ACK controller pods Running in `ack` namespace
- [ ] No `ACK.Terminal` conditions

### 2.4 Spoke Infrastructure

- [ ] Spoke namespace exists with correct annotations
- [ ] KRO instances show Ready conditions

---

## 3. Local CSOC Validation (Host-Based)

### 3.1 Prerequisites (Host)

- [ ] Kind installed on host: `kind version`
- [ ] MFA session active (Tier 1 credentials in `~/.aws/credentials`)

### 3.2 Cluster Lifecycle

```bash
bash scripts/kind-local-test.sh create
kubectl cluster-info --context kind-gen3-local
```

- [ ] Kind cluster `gen3-local` created
- [ ] kubectl connects via kubeconfig

### 3.3 Bootstrap Stack

```bash
bash scripts/kind-local-test.sh install
```

- [ ] ArgoCD namespace running
- [ ] Cluster Secret `local-aws-dev` exists with correct labels/annotations
- [ ] Bootstrap ApplicationSets exist: `local-addons`, `local-aws-dev-infra-instance`

### 3.4 ACK Credential Injection

```bash
bash scripts/kind-local-test.sh inject-creds
```

- [ ] `ack-aws-credentials` Secret exists in `ack` namespace
- [ ] ACK controller pods restart with credentials

### 3.5 ArgoCD Reconciliation

- [ ] ArgoCD UI at `localhost:8080`
- [ ] `kro-csoc-rgs` Application Healthy/Synced
- [ ] All 18 RGDs Active (9 production + 9 test)

### 3.6 KRO Capability Tests

```bash
bash scripts/kind-local-test.sh test
```

- [ ] Tests 1–5 (ConfigMap-only): all produce expected data
- [ ] Test 6 (SG conditional): AWS SecurityGroups created
- [ ] Tests 7a/7b (cross-RGD): producer SG > bridge > consumer reads SG ID
- [ ] Test 8 (chained orValue): both variants produce correct bridge ConfigMaps

### 3.7 Status Report

```bash
bash scripts/kro-status-report.sh
```

- [ ] Generates without errors
- [ ] All sections populate

### 3.8 Cleanup

```bash
bash scripts/kind-local-test.sh destroy
```

- [ ] Kind cluster deleted
- [ ] AWS test resources cleaned up (ACK deletion policy)

---

## 4. Regression Checks

- [ ] `container-init.sh` runs successfully (EKS unaffected)
- [ ] `local-infra-instances.yaml` only matches `fleet_member: control-plane` clusters
- [ ] Test RGDs on EKS inert (no test instances deployed to EKS)



---

## 1. Pre-Merge Checks (Before PR Merge)

### 1.1 File Integrity

- [ ] All 9 test RGD files in `charts/resource-groups/templates/` match gen3-dev originals
- [ ] All 9 production RGD files unchanged from pre-merge state
- [ ] `local-aws-dev/` directory tree has all 19 files (7 infra + 9 tests + 3 support)
- [ ] No secrets, account IDs, or credentials in any committed file
- [ ] `.gitignore` covers `config/local.env` and local CSOC artifacts

### 1.2 Rename Consistency

- [ ] `kro-eks-rgs` does NOT appear anywhere in the repo
- [ ] `kro-local-rgs` does NOT appear anywhere in the repo
- [ ] `kro-csoc-rgs` appears in:
  - `argocd/addons/csoc/addons.yaml`
  - `argocd/addons/local/addons.yaml`
- [ ] Terraform cluster secret labels use `enable_kro_csoc_rgs` (not `enable_kro_eks_rgs`)

### 1.3 Script Validation

- [ ] `kind-local-test.sh` references `gen3-kro` repo URL (not `gen3-dev`)
- [ ] `lib-logging.sh` has no gen3-dev-specific references
- [ ] `kro-status-report.sh` references `addons/local/addons.yaml` (correct path)
- [ ] All scripts pass `shellcheck` (no errors)

### 1.4 Dockerfile

- [ ] `docker build -t gen3-kro .` succeeds (default — no Kind)
- [ ] `docker build --build-arg INSTALL_KIND=true -t gen3-kro-local .` succeeds
- [ ] Default build does NOT install Kind (`kind` command not found)
- [ ] Local build DOES install Kind (`kind version` succeeds)
- [ ] Both builds install Terraform, Terragrunt, kubectl, Helm, AWS CLI

### 1.5 DevContainer Files

- [ ] `devcontainer.json` builds and starts (EKS workflow)
- [ ] `devcontainer-local.json` builds and starts (local workflow)
- [ ] `devcontainer-local.json` has `INSTALL_KIND: true` in build args
- [ ] Local devcontainer mounts both `~/.aws/eks-devcontainer` and `~/.gen3-dev`
- [ ] EKS devcontainer mounts only `~/.aws/eks-devcontainer`

---

## 2. EKS CSOC Validation (Post Phase 1)

These checks verify the `kro-csoc-rgs` rename hasn't broken the production
EKS workflow.

### 2.1 ArgoCD Health

- [ ] ArgoCD is accessible via port-forward
- [ ] `argocd app list` shows all applications
- [ ] No applications in `Unknown` or `Error` state
- [ ] `kro-csoc-rgs-*` applications exist (replaced `kro-eks-rgs-*`)

### 2.2 KRO Controller

- [ ] KRO controller pod is Running in `kro` namespace
- [ ] All RGDs are in `Active` condition:
  ```bash
  kubectl get resourcegraphdefinitions -A
  ```

### 2.3 ACK Controllers

- [ ] All ACK controller pods are Running in `ack` namespace
- [ ] ACK resources are synced (no `ACK.Terminal` conditions)

### 2.4 Spoke Infrastructure

- [ ] Spoke namespace exists with correct annotations
- [ ] KRO instances show Ready conditions
- [ ] No regressions in bridge ConfigMaps

---

## 3. Local CSOC Validation (Post Full Merge)

Full end-to-end test of the local Kind CSOC workflow.

### 3.1 Prerequisites (Host)

- [ ] Kind is installed on the host: `kind version`
- [ ] `~/.gen3-dev/` directory exists on the host
- [ ] `~/.aws/eks-devcontainer/credentials` has valid [csoc] profile
- [ ] MFA session is active (Tier 1 credentials)

### 3.2 Cluster Lifecycle

```bash
# Create Kind cluster
bash scripts/kind-local-test.sh create

# Verify cluster
kubectl cluster-info --context kind-gen3-local
kubectl get nodes
```

- [ ] Kind cluster `gen3-local` created successfully
- [ ] kubectl can connect via dedicated kubeconfig

### 3.3 Bootstrap Stack

```bash
# Install ArgoCD + bootstrap
bash scripts/kind-local-test.sh install
```

- [ ] ArgoCD namespace exists with running pods
- [ ] ArgoCD cluster Secret `local-aws-dev` exists with correct labels/annotations
- [ ] Bootstrap ApplicationSets exist:
  - `local-addons`
  - `local-aws-dev-infra-instance`

### 3.4 ACK Credential Injection

```bash
# Inject AWS credentials
bash scripts/kind-local-test.sh inject-creds
```

- [ ] `ack-aws-credentials` Secret exists in `ack` namespace
- [ ] ACK controller deployments have `AWS_SHARED_CREDENTIALS_FILE` env var
- [ ] ACK controller pods restart with credentials

### 3.5 ArgoCD Reconciliation

- [ ] ArgoCD UI accessible at `localhost:8080`
- [ ] KRO controller Application is Healthy/Synced
- [ ] ACK controller Applications are Healthy/Synced
- [ ] `kro-csoc-rgs` Application is Healthy/Synced (not `kro-local-rgs` or `kro-eks-rgs`)
- [ ] All RGDs are Active:
  ```bash
  kubectl get resourcegraphdefinitions -A
  ```
  Expected: 9 production + 9 test RGDs = 18 total

### 3.6 KRO Capability Tests

```bash
# Run tests
bash scripts/kind-local-test.sh test
```

- [ ] Test 1 (forEach): ConfigMaps created with expected data
- [ ] Test 2 (includeWhen): Correct conditional resources based on flags
- [ ] Test 3 (bridge producer): Bridge ConfigMap created with data
- [ ] Test 4 (bridge consumer): Consumer reads producer's bridge data
- [ ] Test 5 (CEL): Dev and prod variants produce correct values
- [ ] Test 6 (SG conditional): SecurityGroups created in AWS (real resources)
- [ ] Test 7a/7b (cross-RGD): Producer SG exists; consumer reads SG ID from bridge
- [ ] Test 8 (chained orValue): Both variants produce correct bridge ConfigMaps

### 3.7 Status Report

```bash
bash scripts/kro-status-report.sh
```

- [ ] Report generates without errors
- [ ] All sections populate (KRO, ACK, instances, ArgoCD)
- [ ] Output saved to `outputs/reports/kro-status.ansi`

### 3.8 Cleanup

```bash
bash scripts/kind-local-test.sh destroy
```

- [ ] Kind cluster deleted
- [ ] No orphaned Docker containers
- [ ] AWS resources from tests 6/7 are cleaned up (ACK deletion policy)

---

## 4. Regression Checks

### 4.1 EKS Workflow Unaffected

- [ ] `container-init.sh` still runs successfully
- [ ] `install.sh` Terraform commands work
- [ ] Existing spoke infrastructure unchanged
- [ ] No new ArgoCD applications appear on EKS from local-only content

### 4.2 No Cross-Contamination

- [ ] `local-addons.yaml` bootstrap only matches `fleet_member: control-plane` clusters
- [ ] `local-aws-dev/` instance files only deploy to the local Kind cluster
- [ ] Test RGDs exist on EKS cluster but no test instances are created (inert)

---

## 5. Quick Smoke Test Commands

```bash
# === EKS CSOC ===
# Verify rename
grep -r "kro-eks-rgs" argocd/ && echo "FAIL: old name found" || echo "PASS"
grep -r "kro-local-rgs" argocd/ && echo "FAIL: old name found" || echo "PASS"
grep -r "kro-csoc-rgs" argocd/addons/ | wc -l  # Should be 2 (csoc + local)

# === Local CSOC (from inside devcontainer-local) ===
kind version                     # Should succeed
kubectl cluster-info             # Should show gen3-local
kubectl get rgd -A | wc -l      # Should be 18+ (9 prod + 9 test)
kubectl get pods -n ack          # All ACK controllers Running
kubectl get pods -n kro          # KRO controller Running
kubectl get pods -n argocd       # ArgoCD pods Running
```

---

## 6. Sign-Off

| Check | Reviewer | Date | Status |
|-------|----------|------|--------|
| File inventory matches plan 01 | | | |
| EKS CSOC regression test | | | |
| Local CSOC E2E test | | | |
| Documentation review | | | |
| PR approved | | | |
