# ACK Cross-Account Resource Management (CARM) — Resolution Plan

## Date: Current Session
## Status: EXECUTING

---

## 1. Problem Summary

The `spoke1-dev` KRO `AwsGen3Infra1Flat` instance is stuck `IN_PROGRESS` because the ACK EC2 controller cannot assume the spoke workload role (`ack-workload-ack-controller`) via `sts:AssumeRole`. The VPC resource shows:

```
ACK.Recoverable: AccessDenied: User: arn:aws:sts::123456789012:assumed-role/gen3-csoc-dev-ack-shared-csoc-source/... not authorized to perform sts:AssumeRole on resource: arn:aws:iam::123456789012:role/ack-workload-ack-controller
```

Even though `ACK.IAMRoleSelected: Selected` confirms the IAMRoleSelector CRD is working correctly.

---

## 2. Root Cause Analysis

### 2.1 Chain of Issues (resolved in order)

| # | Issue | Fix | Status |
|---|-------|-----|--------|
| 1 | `ack-role-account-map` ConfigMap missing | Created `carm-configmap.yaml` Helm template | ✅ Committed (cfac4f8) |
| 2 | `IAMRoleSelector=false` feature gate | Added `featureGates.IAMRoleSelector: "true"` to all 17 controllers | ✅ Committed (94ca905) |
| 3 | `IAMRoleSelector=true` + `enableCARM=true` mutual exclusivity | Added `enableCARM: false` to all 17 controllers | ✅ Committed (94ca905) |
| 4 | Source role has no `sts:AssumeRole` permission policy | Applied `ack-carm-spoke-assume` inline policy via CLI | ⚠️ Manual (not in Terraform) |
| 5 | **Spoke trust policy requires `sts:ExternalId`** | **ACK does NOT pass ExternalId — must remove condition** | ❌ CURRENT BLOCKER |

### 2.2 The ExternalId Problem

**Current spoke trust policy** (`ack-workload-ack-controller`):
```json
{
  "Condition": {
    "StringEquals": { "sts:ExternalId": "gen3-csoc-dev" },
    "ArnLike": { "aws:PrincipalArn": "arn:aws:iam::123456789012:role/*ack-shared-*-source" }
  }
}
```

**ACK behavior**: Neither IAMRoleSelector nor legacy CARM pass `ExternalId` when calling `sts:AssumeRole`. This is confirmed by:
- ACK source code: `sts.AssumeRole()` calls only set `RoleArn` and `RoleSessionName`
- Reference KRO example: Spoke roles have `"Condition": {}` (no ExternalId)
- No ACK configuration option exists to inject ExternalId

### 2.3 Why ArnLike Is Sufficient Security

The `ArnLike` condition alone provides adequate protection:
- Only principals matching `arn:aws:iam::123456789012:role/*ack-shared-*-source` can assume the role
- This restricts access to the CSOC ACK source role only
- The source role itself is locked down via OIDC federation (self-managed) or EKS capabilities (AWS-managed)
- ExternalId adds defense-in-depth for confused deputy, but the ArnLike already prevents unauthorized cross-account access

---

## 3. Required Fixes

### Fix 1: Remove ExternalId from Spoke Trust Policy (CRITICAL PATH)

**File**: `terraform/catalog/modules/aws-spoke/main.tf`

Remove the `sts:ExternalId` condition block from the trust policy. The `ArnLike` condition on `aws:PrincipalArn` provides sufficient control.

**Immediate action**: Update the live IAM role trust policy via AWS CLI to unblock, then codify in Terraform.

### Fix 2: Add sts:AssumeRole Permission to CSOC Source Role (Terraform)

**File**: `terraform/catalog/modules/aws-csoc/ack-iam.tf`

Add an `aws_iam_role_policy` resource granting `sts:AssumeRole` and `sts:TagSession` on `arn:aws:iam::*:role/ack-workload-*`. This codifies the manually-applied `ack-carm-spoke-assume` policy.

### Fix 3: Add sts:TagSession to Source Role Policy

The manually-applied policy only has `sts:AssumeRole`. The reference example includes `sts:TagSession` as well. Update both the live policy and the Terraform code.

---

## 4. Execution Plan

### Phase 1: Immediate Unblock (AWS CLI)
1. Update `ack-workload-ack-controller` trust policy — remove ExternalId condition
2. Update source role inline policy — add `sts:TagSession`
3. Verify VPC reconciles successfully

### Phase 2: Codify in Terraform
1. Update `terraform/catalog/modules/aws-spoke/main.tf` — remove ExternalId condition
2. Update `terraform/catalog/modules/aws-csoc/ack-iam.tf` — add `aws_iam_role_policy` for AssumeRole+TagSession
3. Commit and push to Version2

### Phase 3: Verify Full Deployment
1. Monitor RGD instance progression through all resources
2. Confirm `spoke1-dev` reaches `READY` state

---

## 5. Compatibility Notes

### Works for Both AWS-Managed and Self-Managed ACK

The IAMRoleSelector approach with `enableCARM: false` works for both modes:

| Feature | AWS-Managed (EKS Capabilities) | Self-Managed (Helm/ArgoCD) |
|---------|-------------------------------|---------------------------|
| Source role trust | `capabilities.eks.amazonaws.com` | OIDC federation |
| Controller deployment | EKS Capability API | Helm charts via ArgoCD |
| Cross-account method | IAMRoleSelector CRD | IAMRoleSelector CRD |
| CARM ConfigMap | Not needed | Not needed |
| ExternalId support | ❌ Not supported | ❌ Not supported |

The **same spoke trust policy** (ArnLike only, no ExternalId) works for both modes because the trust principal pattern `*ack-shared-*-source` matches the shared source role regardless of how it's assumed.
