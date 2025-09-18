#!/usr/bin/env bash
###################################################################################################################################################
# Post-terraform-apply script
###################################################################################################################################################
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# 0. Connect to the cluster and update kubeconfig
#-------------------------------------------------------------------------------------------------------------------------------------------------#
mkdir -p "$OUTPUTS_DIR/argo"
aws eks update-kubeconfig --name "$HUB_CLUSTER_NAME" --alias "$HUB_CLUSTER_NAME" 
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# 1. Collect the Argo CD host and credentials
#-------------------------------------------------------------------------------------------------------------------------------------------------#
ARGO_HOST=$(kubectl get svc argocd-server -n argocd \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ARGO_USERNAME="admin"
ARGO_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
            -o jsonpath='{.data.password}' | base64 -d)
echo "Argo CD Host: $ARGO_HOST"
echo "Argo CD Username: $ARGO_USERNAME"
echo "Argo CD Password: $ARGO_PASS"
# Save credentials to a file
echo "ARGO_HOST:
$ARGO_HOST" > "$OUTPUTS_DIR/argo/argocd-credentials.txt"
echo "ARGO_USERNAME:
$ARGO_USERNAME" >> "$OUTPUTS_DIR/argo/argocd-credentials.txt"
echo "ARGO_PASS:
$ARGO_PASS" >> "$OUTPUTS_DIR/argo/argocd-credentials.txt"

argocd login "$ARGO_HOST" --username="admin" --password="$ARGO_PASS" --grpc-web --insecure --skip-test-tls
###################################################################################################################################################
# End of file
###################################################################################################################################################
