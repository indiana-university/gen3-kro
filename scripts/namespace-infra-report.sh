#!/usr/bin/env bash
# ============================================================================
# Namespace Infrastructure Report — Per-Spoke Resource Inventory
# ============================================================================
# Usage: ./scripts/namespace-infra-report.sh <namespace>
#
# Produces a comprehensive report of infrastructure resources in a spoke
# namespace, organized by deployment phase and dependency order.
# ============================================================================
set -euo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RESET='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'

header() { echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════════════${RESET}"; echo -e "${CYAN}${BOLD}  $1${RESET}"; echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${RESET}\n"; }
section() { echo -e "${GREEN}${BOLD}▶ $1${RESET}\n"; }
note() { echo -e "${DIM}$1${RESET}"; }

# ── Argument parsing ───────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <namespace>"
  echo ""
  echo "Example: $0 spoke1"
  exit 1
fi

NAMESPACE="$1"

# Verify namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "Error: namespace '$NAMESPACE' does not exist"
  exit 1
fi

# ============================================================================
# PHASE 1: Pre-RGD Resources (ACK CARM, IAMRoleSelector)
# ============================================================================
report_pre_rgd() {
  header "PRE-RGD RESOURCES — Cross-Account Setup (Wave 5)"

  section "IAMRoleSelector (CARM)"
  note "Maps this namespace to a spoke AWS account IAM role"
  kubectl get iamroleselectors -n "$NAMESPACE" -o custom-columns=\
'NAME:.metadata.name,ROLE_ARN:.spec.roleARN,ACCOUNT:.metadata.annotations.aws-account-id,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No IAMRoleSelectors found)"

  echo ""
  section "CARM ConfigMap Reference"
  note "Namespace-to-account mapping in ack-system ConfigMap"
  kubectl get configmap ack-role-account-map -n ack-system -o yaml 2>/dev/null \
    | grep -A1 "$NAMESPACE:" || echo "(No CARM entry for $NAMESPACE)"
  echo ""
}

# ============================================================================
# PHASE 2: RGD-Deployed Resources (KRO AwsGen3Infra1Flat outputs)
# ============================================================================
report_rgd_resources() {
  header "RGD-DEPLOYED RESOURCES — KRO AwsGen3Infra1Flat (Wave 30)"

  # Find the KRO instance in this namespace
  INSTANCE_NAME=$(kubectl get awsgen3infra1flat -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

  if [[ -z "$INSTANCE_NAME" ]]; then
    note "No AwsGen3Infra1Flat instance found in namespace $NAMESPACE"
    return
  fi

  section "KRO Instance"
  kubectl get awsgen3infra1flat "$INSTANCE_NAME" -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,STATE:.status.conditions[0].reason,AGE:.metadata.creationTimestamp'

  echo ""
  note "═══ Dependency Order (bottom → top) ═══"
  echo ""

  # Layer 0: KMS Keys (foundation — encryption for everything)
  section "Layer 0: KMS Keys"
  note "Encryption keys for logging, database, search, and platform"
  kubectl get keys.kms.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,KEY_ARN:.status.ackResourceMetadata.arn,STATE:.status.keyState,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No KMS keys found)"

  echo ""

  # Layer 1: VPC
  section "Layer 1: VPC"
  note "Virtual Private Cloud — foundation for all network resources"
  kubectl get vpcs.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,VPC_ID:.status.vpcID,CIDR:.spec.cidrBlocks[0],STATE:.status.state,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No VPCs found)"

  echo ""

  # Layer 2: Internet Gateway (VPC dependency)
  section "Layer 2: Internet Gateway"
  note "Enables internet access for public subnets"
  kubectl get internetgateways.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,IGW_ID:.status.internetGatewayID,ATTACHMENTS:.status.attachments[0].state,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No IGWs found)"

  echo ""

  # Layer 3: Subnets (VPC + AZ dependency)
  section "Layer 3: Subnets"
  note "Public, Private, and Database subnets across availability zones"
  kubectl get subnets.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,SUBNET_ID:.status.subnetID,AZ:.spec.availabilityZone,CIDR:.spec.cidrBlock,STATE:.status.state' 2>/dev/null \
    || echo "(No subnets found)"

  echo ""

  # Layer 4: Elastic IPs (for NAT)
  section "Layer 4: Elastic IPs"
  note "Static public IPs for NAT Gateways"
  kubectl get elasticipaddresses.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,ALLOCATION_ID:.status.allocationID,PUBLIC_IP:.status.publicIP,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No Elastic IPs found)"

  echo ""

  # Layer 5: NAT Gateways (Subnet + EIP dependency)
  section "Layer 5: NAT Gateways"
  note "Enables private subnets to reach internet (for package downloads, AWS APIs)"
  kubectl get natgateways.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,NAT_GW_ID:.status.natGatewayID,SUBNET:.spec.subnetID,STATE:.status.state' 2>/dev/null \
    || echo "(No NAT Gateways found)"

  echo ""

  # Layer 6: Route Tables (VPC + IGW + NAT dependency)
  section "Layer 6: Route Tables"
  note "Routing rules for public, private, and database subnets"
  kubectl get routetables.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,RT_ID:.status.routeTableID,VPC:.spec.vpcID,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No route tables found)"

  echo ""

  # Layer 7: Security Groups (VPC dependency)
  section "Layer 7: Security Groups"
  note "Firewall rules for EKS and Aurora"
  kubectl get securitygroups.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,SG_ID:.status.id,VPC:.spec.vpcID,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No security groups found)"

  echo ""

  # Layer 8: IAM Roles (independent, but needed before EKS/Aurora)
  section "Layer 8: IAM Roles"
  note "Service roles for EKS cluster, node groups, and ArgoCD spoke registration"
  kubectl get roles.iam.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,ROLE_ARN:.status.ackResourceMetadata.arn,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No IAM roles found)"

  echo ""

  # Layer 9: S3 Buckets (independent)
  section "Layer 9: S3 Buckets"
  note "Object storage for logging, data, and uploads"
  kubectl get buckets.s3.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,LOCATION:.status.location.locationConstraint,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No S3 buckets found)"

  echo ""

  # Layer 10: RDS DB Subnet Group (Subnets dependency)
  section "Layer 10: DB Subnet Group"
  note "Aurora-eligible subnets across AZs"
  kubectl get dbsubnetgroups.rds.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,ARN:.status.ackResourceMetadata.arn,STATE:.status.subnetGroupStatus,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No DB subnet groups found)"

  echo ""

  # Layer 11: Aurora Cluster (DB Subnet Group + SG + IAM dependency)
  section "Layer 11: Aurora PostgreSQL Cluster"
  note "Primary database cluster resource"
  kubectl get dbclusters.rds.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,ENDPOINT:.status.endpoint,READER:.status.readerEndpoint,ENGINE:.spec.engine,STATUS:.status.status' 2>/dev/null \
    || echo "(No Aurora clusters found)"

  echo ""

  # Layer 12: Aurora Instances (Cluster dependency)
  section "Layer 12: Aurora DB Instances"
  note "Compute instances for Aurora cluster (writer + reader)"
  kubectl get dbinstances.rds.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,CLASS:.spec.dbInstanceClass,AZ:.status.availabilityZone,STATUS:.status.dbInstanceStatus,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No Aurora instances found)"

  echo ""

  # Layer 13: EKS Cluster (VPC + Subnets + SG + IAM dependency)
  section "Layer 13: EKS Cluster"
  note "Spoke Kubernetes cluster managed by KRO"
  kubectl get clusters.eks.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,VERSION:.spec.version,ENDPOINT:.status.endpoint,STATUS:.status.status,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No EKS clusters found)"

  echo ""

  # Layer 14: EKS Node Groups (EKS Cluster dependency)
  section "Layer 14: EKS Node Groups"
  note "Worker nodes for spoke EKS cluster"
  kubectl get nodegroups.eks.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,INSTANCE_TYPES:.spec.instanceTypes[*],SCALING:.spec.scalingConfig,STATUS:.status.status' 2>/dev/null \
    || echo "(No node groups found)"

  echo ""

  # Layer 15: EKS Access Entry (EKS Cluster + IAM dependency)
  section "Layer 15: EKS Access Entry"
  note "Grants ArgoCD spoke role access to EKS cluster"
  kubectl get accessentries.eks.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,PRINCIPAL:.spec.principalARN,TYPE:.spec.type,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(No access entries found)"

  echo ""

  # Layer 16: EKS Pod Identity Association (EKS Cluster dependency)
  section "Layer 16: Pod Identity Associations"
  note "IRSA-style pod-to-IAM-role mappings"
  kubectl get podidentityassociations.eks.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,SERVICE_ACCOUNT:.spec.serviceAccount,ROLE_ARN:.spec.roleARN,STATUS:.status.associationID' 2>/dev/null \
    || echo "(No pod identity associations found)"

  echo ""
}

# ============================================================================
# PHASE 3: Workload Resources (Wave 40+)
# ============================================================================
report_workload_resources() {
  header "WORKLOAD RESOURCES — ArgoCD Applications & Secrets (Wave 40+)"

  section "ArgoCD Cluster Secret (Spoke Registration)"
  note "Registers this spoke EKS cluster with CSOC ArgoCD"
  kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster \
    -o custom-columns='NAME:.metadata.name,SERVER:.data.server,FLEET_MEMBER:.metadata.labels.fleet_member' 2>/dev/null \
    | grep "$NAMESPACE" || echo "(No cluster secrets found for $NAMESPACE)"

  echo ""

  section "Infrastructure Outputs Secret (for Gen3 apps)"
  note "Non-sensitive infrastructure outputs consumed by workloads"
  kubectl get secrets -n "$NAMESPACE" -l managed-by=kro 2>/dev/null \
    || echo "(No KRO-managed secrets found)"

  echo ""

  section "ArgoCD Applications Targeting This Namespace"
  note "Workload applications deployed to the spoke cluster"
  kubectl get applications -n argocd -o json 2>/dev/null \
    | jq -r --arg ns "$NAMESPACE" '.items[] | select(.spec.destination.name | contains($ns)) | "\(.metadata.name)\t\(.spec.syncPolicy.automated // "manual")\t\(.status.sync.status // "unknown")\t\(.status.health.status // "unknown")"' \
    | awk 'BEGIN {print "NAME\tSYNC_POLICY\tSYNC_STATUS\tHEALTH"} {print}' \
    | column -t -s $'\t' \
    || echo "(No applications found targeting $NAMESPACE)"

  echo ""

  section "External Secrets (Wave 15 on spoke)"
  note "Syncs DB passwords and other secrets from AWS Secrets Manager"
  kubectl get externalsecrets -n "$NAMESPACE" 2>/dev/null \
    || echo "(No ExternalSecrets found — ESO may not be deployed yet)"

  echo ""

  section "Gen3 Workload Pods (if deployed)"
  note "Application pods running on the spoke cluster"
  echo "(This requires kubectl context switch to the spoke cluster — showing CSOC-side resources only)"
  echo "To inspect spoke cluster: aws eks update-kubeconfig --name \$(kubectl get cluster -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}') --region us-east-1"
}

# ============================================================================
# SUMMARY
# ============================================================================
report_summary() {
  header "SUMMARY"

  echo -e "${YELLOW}Namespace:${RESET} $NAMESPACE"
  echo -e "${YELLOW}KRO Instance:${RESET} $(kubectl get awsgen3infra1flat -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo 'None')"
  echo -e "${YELLOW}VPC ID:${RESET} $(kubectl get vpcs.ec2.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].status.vpcID}' 2>/dev/null || echo 'None')"
  echo -e "${YELLOW}EKS Cluster:${RESET} $(kubectl get clusters.eks.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo 'None')"
  echo -e "${YELLOW}Aurora Endpoint:${RESET} $(kubectl get dbclusters.rds.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].status.endpoint}' 2>/dev/null || echo 'None')"

  echo ""
  echo -e "${DIM}Resource counts:${RESET}"
  echo "  KMS Keys:        $(kubectl get keys.kms.services.k8s.aws -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
  echo "  Subnets:         $(kubectl get subnets.ec2.services.k8s.aws -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
  echo "  Security Groups: $(kubectl get securitygroups.ec2.services.k8s.aws -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
  echo "  S3 Buckets:      $(kubectl get buckets.s3.services.k8s.aws -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
  echo "  IAM Roles:       $(kubectl get roles.iam.services.k8s.aws -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
  echo "  Aurora Instances: $(kubectl get dbinstances.rds.services.k8s.aws -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
  echo ""
}

# ── Main ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  Namespace Infrastructure Report                          ║${RESET}"
echo -e "${CYAN}${BOLD}║  KRO + ACK Resources for: ${YELLOW}$(printf '%-31s' "$NAMESPACE")${CYAN}${BOLD}║${RESET}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════╝${RESET}"

report_pre_rgd
report_rgd_resources
report_workload_resources
report_summary

echo ""
note "═══════════════════════════════════════════════════════════"
note "End of report for namespace: $NAMESPACE"
note "═══════════════════════════════════════════════════════════"
echo ""
