# Gen3 KRO Deployment Plan - Consolidated Overview

## Executive Summary
This document outlines the phased deployment strategy for the Gen3 KRO platform. The deployment is broken into 6 distinct, non-overlapping phases that progressively build the infrastructure from foundational components to production workloads.

---

## Phase Overview

| Phase | Name | Duration | Description | Success Criteria |
|-------|------|----------|-------------|------------------|
| 0 | Foundation Setup | 2-3 days | Repository structure, IAM roles, Terraform configuration | Terraform validates, IAM roles exist |
| 1 | Hub Bootstrap | 1-2 days | Deploy hub cluster with ArgoCD and bootstrap ApplicationSet | ArgoCD UI accessible, bootstrap synced |
| 2 | Platform Addons | 2-3 days | Deploy KRO, ACK controllers, platform components | All Wave 0 apps healthy |
| 3 | Resource Graphs | 1 day | Deploy RGDs to hub cluster | All RGDs available, KRO controller ready |
| 4 | Spoke Infrastructure | 3-5 days | Provision first spoke cluster via graph instances | Spoke cluster accessible, registered with hub |
| 5 | Workload Deployment | 2-3 days | Deploy Gen3 applications to spoke clusters | Gen3 instances running, health checks pass |

**Total Estimated Duration**: 11-17 days (conservative estimate with buffer)

---

## Phase Dependencies

```
Phase 0: Foundation Setup
    ↓
Phase 1: Hub Bootstrap
    ↓
Phase 2: Platform Addons (Wave 0)
    ↓
Phase 3: Resource Graphs (Wave 1)
    ↓
Phase 4: Spoke Infrastructure (Wave 2)
    ↓
Phase 5: Workload Deployment (Wave 3)
```

**Critical Path**: Each phase is a hard dependency for the next. Phases cannot be parallelized without significant risk.

---

## Phase Summaries

### Phase 0: Foundation Setup
**Goal**: Prepare all prerequisites for deployment

**Key Activities**:
- Finalize repository structure
- Create IAM roles for ACK controllers (15 roles × 2 environments = 30 roles)
- Configure Terraform state backend
- Set up AWS Secrets Manager for cluster credentials
- Validate all configuration files

**Deliverables**:
- IAM roles with IRSA trust policies
- Terraform backend configured
- All `values.yaml` files populated with real role ARNs
- Pre-deployment validation passing

**Risk Level**: Low (preparation only, no deployments)

---

### Phase 1: Hub Bootstrap
**Goal**: Deploy hub cluster with ArgoCD

**Key Activities**:
- Run `terraform apply` to create hub EKS cluster
- Deploy ArgoCD via Terraform module
- Deploy bootstrap ApplicationSet
- Verify ArgoCD can sync from git repository

**Deliverables**:
- Hub EKS cluster running
- ArgoCD accessible via LoadBalancer/Ingress
- Bootstrap ApplicationSet synced
- All 4 child ApplicationSets created (but not synced yet)

**Risk Level**: Medium (foundational infrastructure)

---

### Phase 2: Platform Addons
**Goal**: Deploy Wave 0 addons to hub cluster

**Key Activities**:
- Sync addons ApplicationSet
- Deploy KRO controller (critical dependency)
- Deploy ACK controllers (15 controllers)
- Deploy external-secrets, kyverno, metrics-server

**Deliverables**:
- KRO controller running in `kro-system` namespace
- All 15 ACK controllers running in `ack-system` namespace
- External Secrets syncing from AWS Secrets Manager
- Kyverno policies active

**Risk Level**: High (many moving parts, IAM dependencies)

---

### Phase 3: Resource Graphs
**Goal**: Deploy RGDs to hub cluster

**Key Activities**:
- Sync graphs ApplicationSet
- Deploy all RGDs from `shared/graphs/aws/`
- Validate RGD CRDs are registered
- Test RGD with a dummy instance

**Deliverables**:
- 6 RGDs deployed: EFS, EKS Cluster, IAM Addons, IAM Roles, VPC Network
- `kubectl get rgd` shows all RGDs
- KRO controller reconciling RGDs

**Risk Level**: Low (declarative resources, no infrastructure created yet)

---

### Phase 4: Spoke Infrastructure
**Goal**: Provision first spoke cluster

**Key Activities**:
- Create spoke1 configuration in `argocd/spokes/spoke1/`
- Sync graph-instances ApplicationSet
- Monitor KRO provisioning spoke cluster in AWS
- Register spoke cluster with hub ArgoCD
- Deploy Wave 0 addons to spoke cluster

**Deliverables**:
- Spoke1 EKS cluster running in spoke AWS account
- Spoke registered with hub ArgoCD (cluster secret created)
- ACK controllers deployed to spoke
- Spoke accessible from hub

**Risk Level**: High (infrastructure provisioning, cross-account setup)

---

### Phase 5: Workload Deployment
**Goal**: Deploy Gen3 applications to spoke

**Key Activities**:
- Create Gen3 instance config in `argocd/spokes/spoke1/sample.gen3.url.org/`
- Sync gen3-instances ApplicationSet
- Monitor Gen3 deployment to spoke
- Validate Gen3 services are running
- Perform smoke tests

**Deliverables**:
- Gen3 application running in spoke cluster
- All Gen3 services healthy
- Portal accessible (if configured)
- Data ingestion tested

**Risk Level**: Medium (application-level, depends on Phase 4)

---

## Go/No-Go Decision Points

### Before Phase 1
- [ ] All IAM roles created and validated
- [ ] Terraform state backend configured
- [ ] AWS credentials configured
- [ ] Git repository accessible from AWS

### Before Phase 2
- [ ] Hub cluster healthy
- [ ] ArgoCD accessible and syncing
- [ ] Bootstrap ApplicationSet synced

### Before Phase 3
- [ ] KRO controller running
- [ ] All ACK controllers healthy
- [ ] No errors in ApplicationSet controller logs

### Before Phase 4
- [ ] All RGDs deployed
- [ ] `kubectl get rgd` shows expected resources
- [ ] Test instance successfully created

### Before Phase 5
- [ ] Spoke cluster provisioned
- [ ] Spoke registered with hub
- [ ] Spoke addons deployed

---

## Rollback Strategy

### Phase 1-2 Rollback
- Run `terraform destroy` to remove hub cluster
- Delete ArgoCD namespace
- Re-run from Phase 1

### Phase 3 Rollback
- Delete graphs ApplicationSet: `kubectl delete applicationset graphs -n argocd`
- Manually delete RGD CRDs if needed
- Re-sync graphs ApplicationSet

### Phase 4 Rollback
- Delete graph-instances ApplicationSet
- Manually delete EKS cluster from AWS Console (if KRO didn't clean up)
- Remove spoke cluster secret from ArgoCD
- Re-run Phase 4 with fixes

### Phase 5 Rollback
- Delete gen3-instances ApplicationSet
- Manually delete Gen3 namespace
- Re-sync gen3-instances ApplicationSet

---

## Monitoring and Validation

### ArgoCD Health Checks
```bash
# Check ApplicationSets
kubectl get applicationsets -n argocd

# Check Applications
kubectl get applications -n argocd

# Check sync status
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status
```

### Controller Health Checks
```bash
# ACK Controllers
kubectl get pods -n ack-system

# KRO Controller
kubectl get pods -n kro-system

# External Secrets
kubectl get pods -n external-secrets-system
```

### Infrastructure Validation
```bash
# RGDs
kubectl get rgd

# Instances
kubectl get ekscluster

# AWS Resources (via ACK)
kubectl get clusters.eks -A
kubectl get vpcs.ec2 -A
```

---

---

## Communication Plan

### Daily Standups
- Phase status update
- Blockers and risks
- Next steps

### Phase Completion Reviews
- Demo of phase deliverables
- Go/No-Go decision for next phase
- Lessons learned

---

## Success Metrics

### Phase 1-2 Success
- ArgoCD uptime: 99.9%
- All controllers running: 100%
- Zero sync errors in ArgoCD

### Phase 3 Success
- All RGDs deployed: 6/6
- KRO controller healthy: Yes
- Test instance created successfully: Yes

### Phase 4 Success
- Spoke cluster provisioned: Yes
- Spoke registered with hub: Yes
- Cross-cluster communication working: Yes

### Phase 5 Success
- Gen3 application healthy: Yes
- All services running: 100%
- Smoke tests passing: 100%

---

## Detailed Phase Plans

See individual phase documents for detailed implementation steps:
- [Phase 0: Foundation Setup](./Phase0.md)
- [Phase 1: Hub Bootstrap](./Phase1.md)
- [Phase 2: Platform Addons](./Phase2.md)
- [Phase 3: Resource Graphs](./Phase3.md)
- [Phase 4: Spoke Infrastructure](./Phase4.md)
- [Phase 5: Workload Deployment](./Phase5.md)

---

## Appendix: Timeline

### Week 1
- Days 1-2: Phase 0 (Foundation Setup)
- Days 3-4: Phase 1 (Hub Bootstrap)
- Day 5: Phase 2 start (Platform Addons)

### Week 2
- Days 1-2: Phase 2 completion
- Day 3: Phase 3 (Resource Graphs)
- Days 4-5: Phase 4 start (Spoke Infrastructure)

### Week 3
- Days 1-3: Phase 4 completion
- Days 4-5: Phase 5 (Workload Deployment)

### Week 4 (Buffer)
- Troubleshooting, documentation, handoff

---

**Document Version**: 1.0
**Last Updated**: October 12, 2025
**Owner**: boadeyem
