#!/usr/bin/env bash
###################################################################################################################################################
# get-cluster-info.sh
###################################################################################################################################################
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# 2. sanity checks
#-------------------------------------------------------------------------------------------------------------------------------------------------#
IFS=$'\n\t'

[[ -z "${OUTPUTS_DIR:-}" ]] && {
  echo "ERROR: OUTPUTS_DIR env var must be set." >&2
  exit 1
}
command -v argocd >/dev/null || { echo "argocd CLI not found"; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl CLI not found"; exit 1; }
command -v jq >/dev/null || { echo "jq not found"; exit 1; }

OUT_BASE="$OUTPUTS_DIR/argo/troubleshoot"
mkdir -p "$OUT_BASE"

RUN_ID="$(date +%Y%m%d_%H%M%S)"
log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*" | tee -a "$OUT_BASE/run_${RUN_ID}.log"; }
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# 3. global cluster‑level info
#-------------------------------------------------------------------------------------------------------------------------------------------------#
log "Capturing cluster‑level information…"
argocd version                          >  "$OUT_BASE/argocd_version.txt"  2>&1
argocd cluster list --output wide       >  "$OUT_BASE/cluster_list.txt"    2>&1
argocd app list                         >  "$OUT_BASE/app_list.txt"        2>&1
kubectl config current-context          >  "$OUT_BASE/kubectl_context.txt" 2>&1
kubectl get events -A --sort-by=.lastTimestamp \
                                        >  "$OUT_BASE/cluster_events.txt"  2>&1
kubectl get nodes -o wide               >  "$OUT_BASE/nodes.txt"           2>&1
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# 4. determine Applications to inspect
#-------------------------------------------------------------------------------------------------------------------------------------------------#
mapfile -t APPS < <(argocd app list -o name)
(( ${#APPS[@]} == 0 )) && { log "No applications found."; exit 0; }
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# 5. per‑application deep dive
#-------------------------------------------------------------------------------------------------------------------------------------------------#
sanitize() {
  local str="$1"
  # Replace all non-matching characters with "_"
  str="${str//[^A-Za-z0-9._-]/_}"
  printf '%s\n' "$str"
}


for APP in "${APPS[@]}"; do
  APP_SAFE="$(sanitize "$APP")"
  APP_DIR="$OUT_BASE/$APP_SAFE"
  mkdir -p "$APP_DIR"

  log "▶ Gathering details for $APP …"

  # 5.1 Hard refresh & full get
  argocd app get "$APP" --hard-refresh \
               > "$APP_DIR/app_get.txt"       2>&1 || true

  # 5.2 Parse destination for namespace / server
  DEST_JSON="$(argocd app get "$APP" -o json)"
  DEST_NS="$(jq -r '.spec.destination.namespace // "default"' <<<"$DEST_JSON")"
  DEST_SERVER="$(jq -r '.spec.destination.server' <<<"$DEST_JSON")"
  printf '%s\n' "namespace=$DEST_NS" "server=$DEST_SERVER" \
               > "$APP_DIR/destination.txt"

  # 5.3 Rendered manifest
  argocd app manifest "$APP" \
               > "$APP_DIR/manifest.yaml"     2>&1 || true

  # 5.4 Managed resources
  argocd app resources "$APP" \
               > "$APP_DIR/resources.txt"     2>&1 || true

  # 5.5 Live diff (server‑side)
  argocd app diff "$APP" \
               > "$APP_DIR/diff.txt"          2>&1 || true

  # 5.6 Namespace existence & details
  kubectl get ns "$DEST_NS" -o yaml \
               > "$APP_DIR/namespace.yaml"    2>&1 || echo "Namespace $DEST_NS missing" >"$APP_DIR/namespace.yaml"

  # 5.7 Controller logs (last 2 h, grep by app name)
  kubectl -n argocd logs deploy/argocd-applicationset-controller --since=2h | grep -F "$APP" \
               > "$APP_DIR/controller.log"    2>&1 || true
  
  # 5.8 Repo server logs (last 2 h, grep by app name)
  kubectl -n argocd logs deploy/argocd-repo-server --since=2h | grep -F "$APP" \
               > "$APP_DIR/repo.log"          2>&1 || true

  # 5.9 Events for the app’s namespace
  kubectl get events -n "$DEST_NS" --sort-by=.lastTimestamp \
               > "$APP_DIR/ns_events.txt"     2>&1 || true
done
#-------------------------------------------------------------------------------------------------------------------------------------------------#
log "Diagnostics complete. Artifacts in $OUT_BASE"
###################################################################################################################################################
# End of Script
###################################################################################################################################################
