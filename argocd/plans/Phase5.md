# Phase 5: Workload Deployment

**Dependencies**: Phase 4 complete (spoke infrastructure running)

---

## Overview

Phase 5 deploys Gen3 applications to spoke clusters. This is the final deployment phase where actual workloads run. The `gen3-instances` ApplicationSet (Wave 3) discovers Gen3 application manifests in spoke directories and deploys them to the corresponding spoke clusters.

This phase transforms the infrastructure into a fully operational Gen3 data commons platform.

---

## Objectives

1. ✅ Sync gen3-instances ApplicationSet (Wave 3)
2. ✅ Deploy Gen3 applications to spoke1
3. ✅ Validate Gen3 services running
4. ✅ Configure ingress and DNS
5. ✅ Run smoke tests
6. ✅ Enable monitoring and alerting
7. ✅ Hand off to operations

---

## Prerequisites

- Phase 4 completed (spoke1 cluster healthy)
- All spoke addons Running
- DNS zone configured (e.g., gen3.yourdomain.org)
- SSL certificates available (AWS ACM or cert-manager)
- Gen3 application manifests ready in `spokes/spoke1/sample.gen3.url.org/`

---

## Task Breakdown

### Task 5.1: Pre-Deployment Validation (30 minutes)

**Objective**: Verify spoke cluster ready for workloads

#### Step 5.1.1: Verify Spoke Cluster Health

```bash
# Switch to spoke context
kubectl config use-context spoke1

# Check all system pods Running
kubectl get pods -A | grep -v Running | grep -v Completed
# Should show only header

# Check node capacity
kubectl top nodes

# Verify available resources
kubectl describe nodes | grep -A 5 "Allocated resources"

# Ensure sufficient CPU/memory for Gen3 apps
```

#### Step 5.1.2: Verify Gen3 Application Manifests

```bash
# List Gen3 app directories
ls -la argocd/spokes/spoke1/sample.gen3.url.org/

# Expected structure:
# argocd/spokes/spoke1/sample.gen3.url.org/
#   kustomization.yaml
#   deployments/
#   services/
#   ingresses/
#   configmaps/
#   secrets/

# Validate kustomization
kustomize build argocd/spokes/spoke1/sample.gen3.url.org/ | kubectl apply --dry-run=client -f -

# Check for errors
```

#### Step 5.1.3: Verify Gen3-Instances ApplicationSet

```bash
# Switch to hub context
kubectl config use-context hub-staging

# Check ApplicationSet
kubectl get applicationset gen3-instances -n argocd

# Verify sync wave
kubectl get applicationset gen3-instances -n argocd -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/sync-wave}'
# Expected: 3

# Check generators
kubectl get applicationset gen3-instances -n argocd -o yaml | grep -A 20 generators
```

**Validation Checklist**:
- [ ] Spoke cluster healthy
- [ ] Sufficient resources available
- [ ] Gen3 manifests valid
- [ ] Gen3-instances ApplicationSet ready (Wave 3)

---

### Task 5.2: Deploy Gen3 Applications (1-2 hours)

**Objective**: Deploy Gen3 data commons applications to spoke

#### Step 5.2.1: Sync Gen3-Instances ApplicationSet

```bash
# Check if Application generated
kubectl get applications -n argocd | grep "sample-gen3"

# Expected: sample-gen3-url-org (or similar)

# View Application details
kubectl get application sample-gen3-url-org -n argocd -o yaml

# Verify:
# - destination.server points to spoke1 cluster
# - source.path: argocd/spokes/spoke1/sample.gen3.url.org

# Sync application
argocd app sync sample-gen3-url-org

# OR enable auto-sync
kubectl patch application sample-gen3-url-org -n argocd \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' \
  --type merge
```

#### Step 5.2.2: Monitor Application Deployment

```bash
# Watch sync progress
watch -n 5 'argocd app get sample-gen3-url-org'

# Check sync status
argocd app wait sample-gen3-url-org --health --timeout=600

# View deployed resources
argocd app resources sample-gen3-url-org

# Expected resources:
# - Deployments: fence, sheepdog, peregrine, portal, etc.
# - Services: corresponding services
# - Ingresses: Gen3 ingress rules
# - ConfigMaps: Gen3 configuration
# - Secrets: credentials, tokens
```

#### Step 5.2.3: Verify Gen3 Pods Running on Spoke

```bash
# Switch to spoke context
kubectl config use-context spoke1

# Check Gen3 namespace
kubectl get namespace | grep gen3
# Or: kubectl get namespace sample-gen3

# List all Gen3 pods
kubectl get pods -n sample-gen3

# Expected pods (example Gen3 deployment):
# fence-xxxx           1/1  Running
# sheepdog-xxxx        1/1  Running
# peregrine-xxxx       1/1  Running
# portal-xxxx          1/1  Running
# indexd-xxxx          1/1  Running
# arborist-xxxx        1/1  Running

# Check pod logs for startup errors
kubectl logs -n sample-gen3 deployment/fence --tail=50
kubectl logs -n sample-gen3 deployment/portal --tail=50

# Verify all pods Running
kubectl wait --for=condition=Ready pod --all -n sample-gen3 --timeout=300s
```

**Validation Checklist**:
- [ ] Gen3 Application synced
- [ ] All Gen3 deployments created
- [ ] All Gen3 pods Running
- [ ] No CrashLoopBackOff errors
- [ ] Logs show successful startup

---

### Task 5.3: Configure Ingress and DNS (1 hour)

**Objective**: Expose Gen3 applications via ingress controller

#### Step 5.3.1: Deploy Ingress Controller (if not already deployed)

```bash
# Check if ingress controller exists
kubectl --context spoke1 get pods -n ingress-nginx

# If not deployed, install via Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

kubectl --context spoke1 create namespace ingress-nginx

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb"

# Wait for LoadBalancer IP
kubectl --context spoke1 get svc -n ingress-nginx ingress-nginx-controller -w
```

#### Step 5.3.2: Get LoadBalancer Endpoint

```bash
# Get LoadBalancer hostname
LB_HOSTNAME=$(kubectl --context spoke1 get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "LoadBalancer: $LB_HOSTNAME"

# Test LoadBalancer reachable
curl -I http://$LB_HOSTNAME
# Should return 404 (no backend yet, but LB working)
```

#### Step 5.3.3: Configure DNS

**Option A: Route53 via ACK (automated)**
```bash
kubectl --context spoke1 apply -f - <<EOF
apiVersion: route53.services.k8s.aws/v1alpha1
kind: RecordSet
metadata:
  name: sample-gen3-alias
  namespace: sample-gen3
spec:
  name: sample.gen3.yourdomain.org
  type: A
  aliasTarget:
    dnsName: $LB_HOSTNAME
    hostedZoneID: <hosted-zone-id>
    evaluateTargetHealth: true
  hostedZoneID: <hosted-zone-id>
EOF

# Wait for DNS propagation
kubectl --context spoke1 wait --for=condition=ACK.ResourceSynced recordset/sample-gen3-alias -n sample-gen3
```

**Option B: Manual Route53 (via CLI)**
```bash
# Create Route53 record
aws route53 change-resource-record-sets \
  --hosted-zone-id <hosted-zone-id> \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "sample.gen3.yourdomain.org",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "<nlb-hosted-zone-id>",
          "DNSName": "'"$LB_HOSTNAME"'",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

#### Step 5.3.4: Verify DNS Resolution

```bash
# Test DNS resolution
dig sample.gen3.yourdomain.org

# Should return LoadBalancer IP

# Test HTTP access
curl -I http://sample.gen3.yourdomain.org

# Should return 200 (or 302 redirect)
```

**Validation Checklist**:
- [ ] Ingress controller deployed
- [ ] LoadBalancer created
- [ ] DNS record created
- [ ] DNS resolves correctly
- [ ] HTTP access working

---

### Task 5.4: Configure SSL/TLS (1 hour)

**Objective**: Enable HTTPS for Gen3 applications

#### Step 5.4.1: Deploy Cert-Manager (if using Let's Encrypt)

```bash
# Install cert-manager
kubectl --context spoke1 apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager pods
kubectl --context spoke1 wait --for=condition=Ready pod --all -n cert-manager --timeout=300s

# Create ClusterIssuer for Let's Encrypt
kubectl --context spoke1 apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@yourdomain.org
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

#### Step 5.4.2: Update Ingress with TLS

```bash
# Update Gen3 ingress to use TLS
kubectl --context spoke1 patch ingress gen3-ingress -n sample-gen3 -p '{
  "spec": {
    "tls": [{
      "hosts": ["sample.gen3.yourdomain.org"],
      "secretName": "gen3-tls-cert"
    }]
  },
  "metadata": {
    "annotations": {
      "cert-manager.io/cluster-issuer": "letsencrypt-prod",
      "nginx.ingress.kubernetes.io/ssl-redirect": "true"
    }
  }
}'

# Wait for certificate issuance
kubectl --context spoke1 wait --for=condition=Ready certificate/gen3-tls-cert -n sample-gen3 --timeout=600s

# Verify certificate
kubectl --context spoke1 get certificate -n sample-gen3
kubectl --context spoke1 describe certificate gen3-tls-cert -n sample-gen3
```

#### Step 5.4.3: Verify HTTPS Access

```bash
# Test HTTPS
curl -I https://sample.gen3.yourdomain.org

# Should return 200 with valid cert

# Check cert details
openssl s_client -connect sample.gen3.yourdomain.org:443 -servername sample.gen3.yourdomain.org < /dev/null | openssl x509 -noout -text | grep "Subject:\|Issuer:\|Not"

# Should show Let's Encrypt issuer
```

**Validation Checklist**:
- [ ] Cert-manager deployed
- [ ] Certificate issued successfully
- [ ] HTTPS working
- [ ] HTTP redirects to HTTPS
- [ ] Valid SSL certificate

---

### Task 5.5: Smoke Testing (1-2 hours)

**Objective**: Verify Gen3 application functionality

#### Step 5.5.1: Portal Access Test

```bash
# Test Gen3 portal homepage
curl -k https://sample.gen3.yourdomain.org/

# Should return HTML with Gen3 portal

# Test in browser
"$BROWSER" https://sample.gen3.yourdomain.org/

# Verify:
# - Page loads without errors
# - Gen3 branding visible
# - Login button present
```

#### Step 5.5.2: API Endpoint Tests

```bash
# Test Fence (authentication service)
curl -k https://sample.gen3.yourdomain.org/_fence/health

# Expected: {"status": "OK"}

# Test Sheepdog (data submission)
curl -k https://sample.gen3.yourdomain.org/_sheepdog/health

# Expected: {"status": "OK"}

# Test Peregrine (GraphQL API)
curl -k https://sample.gen3.yourdomain.org/_peregrine/health

# Expected: {"status": "OK"}

# Test Indexd (data indexing)
curl -k https://sample.gen3.yourdomain.org/index/health

# Expected: {"status": "OK"}
```

#### Step 5.5.3: Database Connectivity Tests

```bash
# Check if Gen3 services can connect to databases
# (Assumes RDS instances created in Phase 4 or earlier)

# Check Fence logs for DB connection
kubectl --context spoke1 logs -n sample-gen3 deployment/fence | grep -i database

# Should show successful connection

# Test from pod
kubectl --context spoke1 exec -n sample-gen3 deployment/fence -- psql -h <rds-endpoint> -U fence -d fence -c "SELECT 1"

# Should return 1
```

#### Step 5.5.4: Authentication Flow Test

```bash
# Test OAuth login flow (manual)
# 1. Navigate to portal: https://sample.gen3.yourdomain.org/
# 2. Click "Login"
# 3. Complete OAuth flow (Google, CILogon, etc.)
# 4. Verify redirect back to portal
# 5. Verify user profile visible

# For automated testing, use Selenium/Playwright scripts
```

**Validation Checklist**:
- [ ] Portal loads successfully
- [ ] All health endpoints return OK
- [ ] Database connectivity working
- [ ] Authentication flow working
- [ ] No errors in logs

---

### Task 5.6: Monitoring and Alerting (1 hour)

**Objective**: Enable observability for Gen3 applications

#### Step 5.6.1: Deploy Prometheus/Grafana (if not already)

```bash
# Add helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --context spoke1

# Wait for pods
kubectl --context spoke1 wait --for=condition=Ready pod --all -n monitoring --timeout=300s
```

#### Step 5.6.2: Configure Gen3 ServiceMonitors

```bash
# Create ServiceMonitor for Gen3 apps
kubectl --context spoke1 apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gen3-services
  namespace: sample-gen3
spec:
  selector:
    matchLabels:
      app: gen3
  endpoints:
  - port: http
    interval: 30s
    path: /metrics
EOF

# Verify ServiceMonitor discovered
kubectl --context spoke1 get servicemonitor -n sample-gen3
```

#### Step 5.6.3: Import Gen3 Dashboards

```bash
# Access Grafana
kubectl --context spoke1 port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open in browser
"$BROWSER" http://localhost:3000

# Login (default: admin/prom-operator)

# Import Gen3 dashboards (if available)
# Or create custom dashboards for:
# - Request rates
# - Error rates
# - Latency percentiles
# - Resource usage
```

#### Step 5.6.4: Configure Alerts

```bash
# Create PrometheusRule for Gen3
kubectl --context spoke1 apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gen3-alerts
  namespace: sample-gen3
spec:
  groups:
  - name: gen3
    interval: 30s
    rules:
    - alert: Gen3ServiceDown
      expr: up{namespace="sample-gen3"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Gen3 service {{ \$labels.pod }} is down"
    - alert: Gen3HighErrorRate
      expr: rate(http_requests_total{namespace="sample-gen3",status=~"5.."}[5m]) > 0.05
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "High error rate in Gen3 service {{ \$labels.service }}"
EOF
```

**Validation Checklist**:
- [ ] Prometheus deployed
- [ ] Grafana accessible
- [ ] Gen3 metrics collected
- [ ] Dashboards created
- [ ] Alerts configured

---

### Task 5.7: Handoff to Operations (1 hour)

**Objective**: Transfer operational responsibility

#### Step 5.7.1: Document Deployment

```bash
# Create deployment summary
cat > /tmp/gen3-deployment-summary.md <<EOF
# Gen3 Deployment Summary

**Environment**: Staging
**Spoke Cluster**: spoke1
**Gen3 Instance**: sample.gen3.yourdomain.org
**Deployment Date**: $(date)

## Endpoints
- Portal: https://sample.gen3.yourdomain.org/
- Fence: https://sample.gen3.yourdomain.org/_fence/
- Sheepdog: https://sample.gen3.yourdomain.org/_sheepdog/
- Peregrine: https://sample.gen3.yourdomain.org/_peregrine/
- Indexd: https://sample.gen3.yourdomain.org/index/

## Infrastructure
- EKS Cluster: spoke1
- Node Count: $(kubectl --context spoke1 get nodes --no-headers | wc -l)
- Namespace: sample-gen3
- Ingress: $(kubectl --context spoke1 get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

## Monitoring
- Grafana: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
- Prometheus: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

## Contacts
- Platform Team: platform-team@yourdomain.org
- Application Team: gen3-team@yourdomain.org
- On-Call: oncall@yourdomain.org
EOF

# Save to repository
cp /tmp/gen3-deployment-summary.md argocd/spokes/spoke1/DEPLOYMENT.md
git add argocd/spokes/spoke1/DEPLOYMENT.md
git commit -m "Add Gen3 deployment summary for spoke1"
git push
```

#### Step 5.7.2: Create Runbooks

```bash
# Create operations runbook
cat > argocd/spokes/spoke1/RUNBOOK.md <<'EOF'
# Gen3 Operations Runbook

## Common Tasks

### Restart a Gen3 Service
kubectl --context spoke1 rollout restart deployment/fence -n sample-gen3

### Scale a Service
kubectl --context spoke1 scale deployment/portal -n sample-gen3 --replicas=3

### View Logs
kubectl --context spoke1 logs -f deployment/fence -n sample-gen3

### Access Database
kubectl --context spoke1 exec -it deployment/fence -n sample-gen3 -- psql -h <rds-endpoint> -U fence -d fence

## Troubleshooting

### Portal Not Loading
1. Check ingress: kubectl --context spoke1 get ingress -n sample-gen3
2. Check service: kubectl --context spoke1 get svc -n sample-gen3
3. Check pods: kubectl --context spoke1 get pods -n sample-gen3
4. Check logs: kubectl --context spoke1 logs deployment/portal -n sample-gen3

### Authentication Failing
1. Check Fence logs: kubectl --context spoke1 logs deployment/fence -n sample-gen3
2. Verify OAuth config: kubectl --context spoke1 get configmap fence-config -n sample-gen3
3. Test health endpoint: curl https://sample.gen3.yourdomain.org/_fence/health

## Emergency Contacts
- Platform: platform-team@yourdomain.org
- Gen3: gen3-team@yourdomain.org
- On-Call: oncall@yourdomain.org
EOF

git add argocd/spokes/spoke1/RUNBOOK.md
git commit -m "Add Gen3 operations runbook for spoke1"
git push
```

#### Step 5.7.3: Schedule Handoff Meeting

- Review deployment architecture
- Walk through runbooks
- Demonstrate monitoring dashboards
- Review alert escalation
- Transfer credentials
- Confirm on-call schedule

**Validation Checklist**:
- [ ] Deployment documented
- [ ] Runbooks created
- [ ] Handoff meeting completed
- [ ] Operations team trained
- [ ] Credentials transferred

---

## Rollback Procedure

### If Phase 5 Fails

**Option 1: Delete Gen3 Application**
```bash
# Delete from ArgoCD
argocd app delete sample-gen3-url-org --cascade

# Verify resources removed from spoke
kubectl --context spoke1 get all -n sample-gen3
# Should be empty

# Keep spoke infrastructure running
```

**Option 2: Rollback to Previous Version**
```bash
# If Gen3 manifests in Git, revert commit
git revert <commit-hash>
git push

# ArgoCD will auto-sync to previous version
argocd app sync sample-gen3-url-org
```

---

## Success Criteria

### Go Live Checklist

- [ ] Gen3 applications deployed and healthy
- [ ] All pods Running (no restarts)
- [ ] Ingress configured with valid SSL
- [ ] DNS resolves correctly
- [ ] All health endpoints return OK
- [ ] Authentication working
- [ ] Smoke tests passing
- [ ] Monitoring enabled
- [ ] Alerts configured
- [ ] Documentation complete
- [ ] Operations team trained

---

## Post-Deployment

### Next 24 Hours
1. Monitor application logs
2. Track resource usage
3. Verify no error spikes
4. Confirm alerting working

### Next 7 Days
1. Performance tuning
2. Capacity planning
3. User acceptance testing
4. Gather feedback

### Next 30 Days
1. Add additional spokes
2. Scale workloads
3. Implement autoscaling
4. Optimize costs

---

## Appendix: Multi-Spoke Deployment

To deploy to additional spokes (spoke2, spoke3, etc.):

```bash
# 1. Create spoke directory
cp -r argocd/spokes/spoke1 argocd/spokes/spoke2

# 2. Update spoke2 values
# Edit argocd/spokes/spoke2/cluster-values/cluster-values.yaml
# Edit argocd/spokes/spoke2/infrastructure/values.yaml
# Edit argocd/spokes/spoke2/sample.gen3.url.org/ (rename to actual domain)

# 3. Commit changes
git add argocd/spokes/spoke2
git commit -m "Add spoke2 configuration"
git push

# 4. ApplicationSets will auto-discover spoke2
# - addons ApplicationSet: deploys controllers to spoke2
# - graph-instances: provisions spoke2 infrastructure
# - gen3-instances: deploys Gen3 apps to spoke2

# 5. Verify deployment
kubectl get applications -n argocd | grep spoke2
```

---

---

**Owner**: BabasanmiAdeyemi  
**Username**: boadeyem  
**Team**: RDS Team
