#!/usr/bin/env bash
###############################################################################
# kro-status-report.sh — KRO + ACK Resource Status Report (Local CSOC)
#
# Produces a structured report of:
#   1. KRO controller health + all RGDs
#   2. ACK controller health (auto-discovered from addons.yaml)
#   3. Active KRO instance status (auto-discovered from infrastructure/ and tests/)
#      — conditions, status fields, bridge ConfigMaps, per-instance ACK resources
#      NOTE: cluster-resources/ and applications/ subdirs are not yet scanned
#   4. ACK-managed AWS resources (all namespaces from infrastructure/ and tests/)
#   5. ArgoCD Application health
#
# Fleet instance directory layout:
#   argocd/local-kind/test/   (local Kind default)
#   argocd/fleet/<cluster>/   (EKS spoke; use --cluster <name>)
#
# Output is always written to outputs/reports/<name>.ansi (ANSI colours preserved).
# Filename is derived from flags; existing files are overwritten unless -ts is used.
#
# Usage:
#   bash scripts/reports/kro-status-report.sh                      # → kro-status.ansi
#   bash scripts/reports/kro-status-report.sh --cluster spoke1     # → kro-status-cluster-spoke1.ansi
#   bash scripts/reports/kro-status-report.sh --ns spoke1          # → kro-status-ns-spoke1.ansi
#   bash scripts/reports/kro-status-report.sh --section kro        # kro | ack | instances | argocd
#   bash scripts/reports/kro-status-report.sh --instance <name>    # filter to one instance
#   bash scripts/reports/kro-status-report.sh --json ./snap.json   # also emit JSON snapshot
#   bash scripts/reports/kro-status-report.sh -ts                  # append timestamp to filename
#
# Mirrors kind-csoc.sh script structure with inline logging helpers.
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

ADDONS_FILE="${REPO_DIR}/argocd/addons/addons.yaml"
INFRA_DIR="${REPO_DIR}/argocd/local-kind/test"

# ── Argument Parsing ──────────────────────────────────────────────────────────
FILTER_CLUSTER=""
FILTER_NS=""
FILTER_INSTANCE=""
FILTER_SECTION=""   # kro | instances | ack | argocd | (empty = all)
JSON_OUT=""
ADD_TIMESTAMP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)   FILTER_CLUSTER="$2"; shift 2 ;;
    --ns)        FILTER_NS="$2";       shift 2 ;;
    --instance)  FILTER_INSTANCE="$2"; shift 2 ;;
    --section)   FILTER_SECTION="$2";  shift 2 ;;
    --json)      JSON_OUT="$2";        shift 2 ;;
    -ts)         ADD_TIMESTAMP=1;      shift ;;
    -h|--help)
      sed -n '4,23p' "$0" | sed -E 's/^#( |$)//'
      exit 0 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Resolve INFRA_DIR from --cluster if provided ─────────────────────────────
if [[ -n "${FILTER_CLUSTER}" ]]; then
  INFRA_DIR="${REPO_DIR}/argocd/fleet/${FILTER_CLUSTER}"
  if [[ ! -d "${INFRA_DIR}" ]]; then
    echo "Error: fleet directory not found: ${INFRA_DIR}"
    exit 1
  fi
fi

# ── Compute output path from active flags ────────────────────────────────────
_build_output_path() {
  local name="kro-status"
  [[ -n "${FILTER_CLUSTER}" ]]   && name+="-cluster-${FILTER_CLUSTER}"
  [[ -n "${FILTER_SECTION}" ]]   && name+="-section-${FILTER_SECTION}"
  [[ -n "${FILTER_NS}" ]]        && name+="-ns-${FILTER_NS}"
  [[ -n "${FILTER_INSTANCE}" ]]  && name+="-instance-${FILTER_INSTANCE}"
  [[ "${ADD_TIMESTAMP}" -eq 1 ]] && name+="-$(date '+%Y%m%d-%H%M%S')"
  echo "${REPO_DIR}/outputs/reports/${name}.ansi"
}

FILE_OUT="$(_build_output_path)"
mkdir -p "$(dirname "${FILE_OUT}")"

# ── Output: always tee to ANSI file (force colour codes regardless of tty) ───
_CLR_RST='\033[0m'
_CLR_GRN='\033[0;32m'
_CLR_YLW='\033[0;33m'
_CLR_RED='\033[0;31m'
_CLR_BLU='\033[0;34m'
_CLR_CYN='\033[0;36m'
_CLR_MAG='\033[0;35m'
_CLR_WHT='\033[1;37m'
_CLR_DIM='\033[2m'
exec > >(tee "${FILE_OUT}") 2>&1

# ── Logging helpers (inline — no lib-logging.sh dependency) ─────────────────
log_info()    { echo -e "${_CLR_BLU}  ℹ${_CLR_RST} $*"; }
log_success() { echo -e "${_CLR_GRN}  ✓${_CLR_RST} $*"; }
log_warn()    { echo -e "${_CLR_YLW}  ⚠${_CLR_RST} $*" >&2; }
log_error()   { echo -e "${_CLR_RED}  ✗${_CLR_RST} $*" >&2; }
log_stage()   { echo -e "\n${_CLR_CYN}>>> [$1]${_CLR_RST} $2"; }
log_banner()  { echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "  $*"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# ── Helper: print separators ─────────────────────────────────────────────────
sep()      { echo -e "${_CLR_DIM}────────────────────────────────────────────────────────────────────${_CLR_RST}"; }
sep_thin() { echo -e "${_CLR_DIM}  ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈${_CLR_RST}"; }

# ── Helper: print intentionally empty section (for --section filtering) ─────
print_empty_section() {
  local title="$1"
  log_banner "${title}"
  echo -e "  ${_CLR_DIM}(empty — filtered by --section=${FILTER_SECTION})${_CLR_RST}"
  echo ""
}

# ── Helper: kubectl quiet (no error on not-found) ─────────────────────────────
kget()  { kubectl get "$@" 2>/dev/null || true; }
kdesc() { kubectl describe "$@" 2>/dev/null || true; }

# ── Helper: auto-discover ACK controller service-account names from addons.yaml
# Returns lines of "ack-<service>-controller" by reading serviceAccount.name
# from each ack-* block in addons.yaml.
discover_ack_controllers() {
  python3 - "${ADDONS_FILE}" <<'PYEOF'
import sys, re

path = sys.argv[1]
try:
    text = open(path).read()
except Exception as e:
    print(f"# error: {e}", file=sys.stderr)
    sys.exit(0)

# Find all serviceAccount.name values under ack-* keys
# Lines match:  name: "ack-XXX-controller"
for m in re.finditer(r'name:\s*["\']?(ack-[\w-]+-controller)["\']?', text):
    print(m.group(1))
PYEOF
}

# ── Helper: auto-discover active instances from infrastructure/ and tests/ ────
# Scans all *.yaml files in both directories, parsing non-commented YAML docs
# to extract deployed KRO instances.
# Outputs lines of "kind|instance-name|namespace"
discover_instances() {
  python3 - "${INFRA_DIR}" <<'PYEOF'
import sys, os, re

base_dir = sys.argv[1]
subdirs = ['infrastructure', 'tests']

for subdir in subdirs:
    scan_dir = os.path.join(base_dir, subdir)
    if not os.path.isdir(scan_dir):
        continue

    for fname in sorted(os.listdir(scan_dir)):
        if not fname.endswith('.yaml'):
            continue
        fpath = os.path.join(scan_dir, fname)
        try:
            text = open(fpath).read()
        except Exception as e:
            print(f"# error reading {fpath}: {e}", file=sys.stderr)
            continue

        # Split into YAML documents on '---' boundary
        docs = re.split(r'^---[ \t]*$', text, flags=re.MULTILINE)

        for doc in docs:
            # Collect only non-commented, non-empty lines
            active = [l for l in doc.splitlines()
                      if l.strip() and not l.lstrip().startswith('#')]
            if not active:
                continue

            kind = name = ns = ''
            for line in active:
                if re.match(r'^kind:\s*\S', line) and not kind:
                    kind = line.split(':', 1)[1].strip()
                elif re.match(r'^  name:\s*\S', line) and not name:
                    name = line.split(':', 1)[1].strip()
                elif re.match(r'^  namespace:\s*\S', line) and not ns:
                    ns = line.split(':', 1)[1].strip()

            if kind and name and ns:
                print(f"{kind}|{name}|{ns}")
PYEOF
}

# ── Helper: derive unique namespaces from infrastructure/ and tests/ ──────────
discover_namespaces() {
  discover_instances | awk -F'|' '{print $3}' | sort -u
}

# ── Helper: extract ACK condition value ───────────────────────────────────────
ack_condition() {
  local ns="$1" restype="$2" resname="$3" condtype="$4"
  kubectl get "${restype}" "${resname}" -n "${ns}" \
    -o jsonpath="{.status.conditions[?(@.type==\"${condtype}\")].status}" 2>/dev/null \
    || echo "unknown"
}

# ── Helper: extract ACK ARN ───────────────────────────────────────────────────
ack_arn() {
  local ns="$1" restype="$2" resname="$3"
  local arn
  arn=$(kubectl get "${restype}" "${resname}" -n "${ns}" \
    -o jsonpath="{.status.ackResourceMetadata.arn}" 2>/dev/null || true)
  # Redact account ID from ARNs when printing (12-digit segment after "arn:aws:*:*:")
  echo "${arn:-}" | sed 's/\(arn:[^:]*:[^:]*:[^:]*:\)[0-9]\{12\}/\1<account>/g'
}

# ── ACK resource types — discovered dynamically from live cluster CRDs ────────
# Lazy-initialised on first call; result cached in _ACK_RESTYPES_CACHE.
# Format per line: "plural.group|Human Label"
_ACK_RESTYPES_CACHE=""
_ensure_ack_restypes() {
  [[ -n "${_ACK_RESTYPES_CACHE}" ]] && return
  # NOTE: do NOT pipe kubectl output to 'python3 - << HEREDOC' — in bash the heredoc
  # overrides the pipe for python3's stdin, causing kubectl to SIGPIPE under pipefail.
  # Pass kubectl output via process substitution as sys.argv[1] instead.
  _ACK_RESTYPES_CACHE=$(python3 - <(kubectl get crd -o json 2>/dev/null) << 'PYEOF'
import sys, json, re
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
results = []
for item in data.get('items', []):
    group = item.get('spec', {}).get('group', '')
    if not group.endswith('.services.k8s.aws'):
        continue
    plural = item['metadata']['name']
    kind   = item.get('spec', {}).get('names', {}).get('kind', '')
    label  = re.sub(r'(?<=[a-z0-9])([A-Z])', r' \1', kind)
    svc    = group.split('.')[0]
    results.append((svc, plural, label))
for svc, plural, label in sorted(results):
    print(f"{plural}|{label}")
PYEOF
)
}

# ── Helper: print ACK resource table for a namespace ─────────────────────────
# usage: report_ack_resources <namespace>
report_ack_resources() {
  local ns="$1"
  local any_found=0

  _ensure_ack_restypes
  while IFS='|' read -r restype label; do
    local items
    items=$(kget "${restype}" -n "${ns}" --no-headers 2>/dev/null) || continue
    [[ -z "${items}" ]] && continue
    any_found=1

    echo -e "  ${_CLR_WHT}${label}${_CLR_RST}"
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      local resname
      resname=$(echo "${line}" | awk '{print $1}')
      local synced terminal arn icon clr
      synced=$(ack_condition "${ns}" "${restype}" "${resname}" "ACK.ResourceSynced")
      terminal=$(ack_condition "${ns}" "${restype}" "${resname}" "ACK.Terminal")
      arn=$(ack_arn "${ns}" "${restype}" "${resname}")

      icon="·"; clr="${_CLR_DIM}"
      if [[ "${terminal}" == "True" ]]; then
        icon="!"; clr="${_CLR_RED}"
      elif [[ "${synced}" == "True" ]]; then
        icon="✓"; clr="${_CLR_GRN}"
      elif [[ "${synced}" == "False" ]]; then
        icon="✗"; clr="${_CLR_YLW}"
      fi

      printf "    ${clr}%s${_CLR_RST}  %-42s  synced=%-7s  ${_CLR_DIM}%s${_CLR_RST}\n" \
        "${icon}" "${resname}" "${synced}" "${arn}"
    done <<< "${items}"
  done <<< "${_ACK_RESTYPES_CACHE}"

  if [[ "${any_found}" -eq 0 ]]; then
    echo -e "  ${_CLR_DIM}(no ACK resources found in namespace ${ns})${_CLR_RST}"
  fi
}

# ── Helper: print KRO instance status ────────────────────────────────────────
# usage: report_instance <kind> <name> <namespace>
report_instance() {
  local kind="$1" name="$2" ns="$3"

  local plural
  plural=$(kubectl get crd --no-headers 2>/dev/null \
    | awk -v k="$(echo "${kind}" | tr '[:upper:]' '[:lower:]')" \
      'tolower($1) ~ k {print $1; exit}') || plural=""

  echo ""
  echo -e "  ${_CLR_WHT}Instance:${_CLR_RST}  ${name}  ${_CLR_DIM}(${kind})${_CLR_RST}"
  echo -e "  ${_CLR_WHT}Namespace:${_CLR_RST} ${ns}"

  if [[ -z "${plural}" ]]; then
    echo -e "  ${_CLR_YLW}⚠  CRD not found — RGD may not be installed yet${_CLR_RST}"
    return
  fi

  local status_ready status_reason status_msg
  status_ready=$(kubectl get "${plural}" "${name}" -n "${ns}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "unknown")
  status_reason=$(kubectl get "${plural}" "${name}" -n "${ns}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || echo "")
  status_msg=$(kubectl get "${plural}" "${name}" -n "${ns}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")

  local icon clr
  icon="·"; clr="${_CLR_DIM}"
  [[ "${status_ready}" == "True" ]]  && { icon="✓"; clr="${_CLR_GRN}"; }
  [[ "${status_ready}" == "False" ]] && { icon="✗"; clr="${_CLR_RED}"; }

  printf "  ${clr}%s  Ready=%-7s${_CLR_RST}  %s\n" "${icon}" "${status_ready}" "${status_reason}"
  if [[ -n "${status_msg}" ]]; then
    printf "     ${_CLR_DIM}msg: %s${_CLR_RST}\n" "${status_msg}"
  fi

  # Status fields (non-conditions)
  echo ""
  echo -e "  ${_CLR_CYN}Status fields:${_CLR_RST}"
  kubectl get "${plural}" "${name}" -n "${ns}" \
    -o jsonpath='{.status}' 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for k, v in d.items():
        if k != 'conditions':
            print(f'    {k}: {v}')
except Exception:
    print('    (status not available)')
" 2>/dev/null || echo "    (status not available)"

  # All conditions
  echo ""
  echo -e "  ${_CLR_CYN}Conditions:${_CLR_RST}"
  local conds
  conds=$(kubectl get "${plural}" "${name}" -n "${ns}" \
    -o jsonpath='{range .status.conditions[*]}{.type}={.status}  {.reason}  {.message}{"\n"}{end}' \
    2>/dev/null || echo "")

  if [[ -z "${conds}" ]]; then
    echo "    (no conditions)"
  else
    while IFS= read -r cline; do
      [[ -z "${cline}" ]] && continue
      local cclr="${_CLR_DIM}"
      [[ "${cline}" == *"=True"* ]]  && cclr="${_CLR_GRN}"
      [[ "${cline}" == *"=False"* ]] && cclr="${_CLR_YLW}"
      echo -e "    ${cclr}${cline}${_CLR_RST}"
    done <<< "${conds}"
  fi

  # Per-instance ACK resources
  echo ""
  echo -e "  ${_CLR_CYN}ACK resources in namespace '${ns}':${_CLR_RST}"
  report_ack_resources "${ns}"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 — KRO Controller + RGDs
# ─────────────────────────────────────────────────────────────────────────────
section_kro() {
  log_banner "SECTION 1 — KRO Controller"

  log_stage "pods" "kro-system"
  kget pods -n kro-system -o wide
  echo ""

  log_stage "RGDs" "ResourceGraphDefinitions"
  kget resourcegraphdefinitions.kro.run --all-namespaces \
    -o custom-columns='NAME:.metadata.name,TOPOLOGICAL_ORDER:.status.topologicalOrder,READY:.status.conditions[?(@.type=="Ready")].status,AGE:.metadata.creationTimestamp' \
    2>/dev/null || kget resourcegraphdefinitions.kro.run --all-namespaces
  echo ""

  log_stage "RGD conditions" "non-Ready only"
  local rgds any_degraded=0
  rgds=$(kubectl get resourcegraphdefinitions.kro.run -A --no-headers \
    -o custom-columns='NAME:.metadata.name' 2>/dev/null || echo "")
  if [[ -n "${rgds}" ]]; then
    while IFS= read -r rgd_name; do
      [[ -z "${rgd_name}" ]] && continue
      local ready
      ready=$(kubectl get resourcegraphdefinitions.kro.run "${rgd_name}" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "unknown")
      if [[ "${ready}" != "True" ]]; then
        any_degraded=1
        echo -e "  ${_CLR_YLW}⚠  ${rgd_name}${_CLR_RST} — Ready=${ready}"
        kubectl get resourcegraphdefinitions.kro.run "${rgd_name}" \
          -o jsonpath='    reason={.status.conditions[?(@.type=="Ready")].reason}{"\n"}    msg={.status.conditions[?(@.type=="Ready")].message}{"\n"}' \
          2>/dev/null || true
      fi
    done <<< "${rgds}"
  fi
  [[ "${any_degraded}" -eq 0 ]] && echo -e "  ${_CLR_GRN}✓  All RGDs are Ready${_CLR_RST}"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — ACK Controllers (auto-discovered from addons.yaml)
# ─────────────────────────────────────────────────────────────────────────────
section_ack_controllers() {
  log_banner "SECTION 2 — ACK Controllers"

  # All ACK controllers share namespace "ack" (consolidated namespace per addons.yaml)
  local ACK_NS="ack"

  # Discover service account names → derive controller deployment names
  local sa_names
  readarray -t sa_names < <(discover_ack_controllers | sort -u)

  if [[ ${#sa_names[@]} -eq 0 ]]; then
    log_warn "No ACK controllers found in ${ADDONS_FILE}"
    return
  fi

  printf "%-45s %-8s %-8s %s\n" "CONTROLLER (SA)" "READY" "TOTAL" "DEPLOYMENT STATUS"
  sep_thin

  for sa_name in "${sa_names[@]}"; do
    [[ -z "${sa_name}" ]] && continue

    # Derive chart-name prefix from SA name: ack-ec2-controller → ec2
    # Pod names in the consolidated "ack" namespace are: <service>-chart-<hash>
    local svc_name="${sa_name#ack-}"          # strip leading "ack-"
    svc_name="${svc_name%-controller}"        # strip trailing "-controller"
    # e.g. "ec2", "eks", "opensearchservice"

    local running total icon clr deploy_status all_pods
    all_pods=$(kubectl get pods -n "${ACK_NS}" --no-headers 2>/dev/null || true)

    running=$(echo "${all_pods}" | grep -c "^${svc_name}-chart.*Running" || true)
    total=$(echo "${all_pods}"   | grep -c "^${svc_name}-chart" || true)
    running="${running:-0}"
    total="${total:-0}"

    if [[ "${running}" -gt 0 ]]; then
      icon="✓"; clr="${_CLR_GRN}"; deploy_status="Running"
    elif [[ "${total}" -gt 0 ]]; then
      icon="⚠"; clr="${_CLR_YLW}"; deploy_status="Degraded"
    else
      icon="✗"; clr="${_CLR_RED}"; deploy_status="Not Ready / No pods"
    fi

    printf "${clr}%s${_CLR_RST}  %-42s  ${clr}%s/%s${_CLR_RST}  %s\n" \
      "${icon}" "${sa_name}" "${running}" "${total}" "${deploy_status}"
  done

  echo ""
  log_stage "All pods in namespace" "${ACK_NS}"
  kget pods -n "${ACK_NS}" -o wide
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — Active KRO Instances (auto-discovered from infrastructure/ and tests/)
# ─────────────────────────────────────────────────────────────────────────────
section_instances() {
  log_banner "SECTION 3 — KRO Instance Status"
  log_info "Auto-discovering instances from ${INFRA_DIR}/{infrastructure,tests}/"

  local entries
  readarray -t entries < <(discover_instances)

  if [[ ${#entries[@]} -eq 0 ]]; then
    log_warn "No active instances found in ${INFRA_DIR}/infrastructure/ or ${INFRA_DIR}/tests/"
  fi

  local found_any=0
  for entry in "${entries[@]}"; do
    [[ -z "${entry}" ]] && continue
    IFS='|' read -r kind name ns <<< "${entry}"
    [[ -z "${kind}" || -z "${name}" || -z "${ns}" ]] && continue

    if [[ -n "${FILTER_INSTANCE}" && "${name}" != "${FILTER_INSTANCE}" ]]; then
      continue
    fi
    if [[ -n "${FILTER_NS}" && "${ns}" != "${FILTER_NS}" ]]; then
      continue
    fi

    found_any=1
    sep
    report_instance "${kind}" "${name}" "${ns}"
    echo ""
  done

  [[ "${found_any}" -eq 0 ]] && echo "  (no instances matched filters)"

  # Bridge ConfigMaps summary
  sep
  echo ""
  log_stage "bridge ConfigMaps" "all namespaces"
  local bridges
  bridges=$(kget configmap --all-namespaces \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,AGE:.metadata.creationTimestamp' \
    2>/dev/null | grep -E "(bridge|crossrgd)" || true)
  if [[ -n "${bridges}" ]]; then
    while IFS= read -r bline; do
      echo -e "  ${_CLR_MAG}${bline}${_CLR_RST}"
    done <<< "${bridges}"
  else
    echo "  (none found)"
  fi
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — ACK AWS Resources (all instance namespaces)
# ─────────────────────────────────────────────────────────────────────────────
section_ack_resources() {
  log_banner "SECTION 4 — ACK-Managed AWS Resources (by namespace)"

  local namespaces
  readarray -t namespaces < <(discover_namespaces)

  if [[ ${#namespaces[@]} -eq 0 ]]; then
    log_warn "No namespaces found — check ${INFRA_DIR}"
    return
  fi

  for ns in "${namespaces[@]}"; do
    [[ -z "${ns}" ]] && continue
    if [[ -n "${FILTER_NS}" && "${ns}" != "${FILTER_NS}" ]]; then
      continue
    fi

    kubectl get namespace "${ns}" &>/dev/null || continue

    sep
    echo ""
    log_stage "namespace" "${ns}"
    echo ""
    report_ack_resources "${ns}"
    echo ""
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — ArgoCD Application Health
# ─────────────────────────────────────────────────────────────────────────────
section_argocd() {
  log_banner "SECTION 5 — ArgoCD Application Health"

  local apps
  apps=$(kget applications.argoproj.io -n argocd \
    -o custom-columns='NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status,REVISION:.status.sync.revision' \
    2>/dev/null || echo "")

  if [[ -z "${apps}" ]]; then
    log_warn "ArgoCD not installed or no applications found"
    echo ""
    return
  fi

  # Print with colour coding per health status
  local header=1
  while IFS= read -r aline; do
    if [[ "${header}" -eq 1 ]]; then
      echo -e "${_CLR_WHT}${aline}${_CLR_RST}"
      header=0
      continue
    fi
    [[ -z "${aline}" ]] && continue
    local aclr="${_CLR_GRN}"
    echo "${aline}" | grep -qE "Degraded|Unknown"    && aclr="${_CLR_RED}"
    echo "${aline}" | grep -qE "Progressing"         && aclr="${_CLR_YLW}"
    echo "${aline}" | grep -qE "OutOfSync|Missing"   && aclr="${_CLR_YLW}"
    echo -e "${aclr}${aline}${_CLR_RST}"
  done <<< "${apps}"
  echo ""

  # Summary of degraded apps
  local degraded
  degraded=$(kubectl get applications.argoproj.io -n argocd --no-headers \
    -o custom-columns='NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status' \
    2>/dev/null | grep -vE "(Healthy.*Synced|^NAME)" || true)
  if [[ -n "${degraded}" ]]; then
    echo ""
    log_warn "Degraded or out-of-sync applications:"
    while IFS= read -r dline; do
      [[ -z "${dline}" ]] && continue
      echo -e "  ${_CLR_YLW}${dline}${_CLR_RST}"
    done <<< "${degraded}"
  else
    log_success "All ArgoCD applications are Healthy and Synced"
  fi
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# JSON dump helper
# ─────────────────────────────────────────────────────────────────────────────
dump_json() {
  [[ -z "${JSON_OUT}" ]] && return

  log_info "Collecting JSON snapshot → ${JSON_OUT}"

  local tmpdir
  tmpdir=$(mktemp -d)

  kubectl get resourcegraphdefinitions.kro.run -A -o json \
    > "${tmpdir}/rgds.json" 2>/dev/null || echo '{"items":[]}' > "${tmpdir}/rgds.json"

  kubectl get applications.argoproj.io -n argocd -o json \
    > "${tmpdir}/argocd.json" 2>/dev/null || echo '{"items":[]}' > "${tmpdir}/argocd.json"

  local ns_list
  readarray -t ns_list < <(discover_namespaces)

  python3 -c "
import json, sys, os
tmpdir = '${tmpdir}'
rgds   = json.load(open(os.path.join(tmpdir,'rgds.json')))
argocd = json.load(open(os.path.join(tmpdir,'argocd.json')))
report = {
  'generatedAt': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
  'cluster':     '${KIND_CLUSTER_NAME:-gen3-local}',
  'rgds':        rgds.get('items',[]),
  'argoCDApps':  argocd.get('items',[]),
}
with open('${JSON_OUT}','w') as f:
  json.dump(report, f, indent=2)
print('  Wrote ${JSON_OUT}')
" 2>/dev/null || log_warn "JSON dump failed (python3 required)"

  rm -rf "${tmpdir}"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
main() {
  log_banner "gen3-kro KRO Status Report — $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo -e "  ${_CLR_WHT}Cluster:${_CLR_RST}    ${KIND_CLUSTER_NAME:-gen3-local}"
  echo -e "  ${_CLR_WHT}KUBECONFIG:${_CLR_RST} ${KUBECONFIG:-~/.kube/config}"
  echo -e "  ${_CLR_WHT}Addons:${_CLR_RST}     ${ADDONS_FILE}"
  echo -e "  ${_CLR_WHT}Instances:${_CLR_RST}  ${INFRA_DIR}/{infrastructure,tests}/"
  echo -e "  ${_CLR_WHT}Filter:${_CLR_RST}     ns=${FILTER_NS:-*}  instance=${FILTER_INSTANCE:-*}  section=${FILTER_SECTION:-all}"
  echo ""

  if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot reach cluster. Is the Kind cluster running?"
    log_info  "Run: docker start gen3-local-control-plane"
    exit 1
  fi

  case "${FILTER_SECTION}" in
    kro)
      section_kro
      print_empty_section "SECTION 2 — ACK Controllers"
      print_empty_section "SECTION 3 — KRO Instance Status"
      print_empty_section "SECTION 4 — ACK-Managed AWS Resources (by namespace)"
      print_empty_section "SECTION 5 — ArgoCD Application Health"
      ;;
    ack)
      print_empty_section "SECTION 1 — KRO Controller"
      section_ack_controllers
      print_empty_section "SECTION 3 — KRO Instance Status"
      section_ack_resources
      print_empty_section "SECTION 5 — ArgoCD Application Health"
      ;;
    instances)
      print_empty_section "SECTION 1 — KRO Controller"
      print_empty_section "SECTION 2 — ACK Controllers"
      section_instances
      print_empty_section "SECTION 4 — ACK-Managed AWS Resources (by namespace)"
      print_empty_section "SECTION 5 — ArgoCD Application Health"
      ;;
    argocd)
      print_empty_section "SECTION 1 — KRO Controller"
      print_empty_section "SECTION 2 — ACK Controllers"
      print_empty_section "SECTION 3 — KRO Instance Status"
      print_empty_section "SECTION 4 — ACK-Managed AWS Resources (by namespace)"
      section_argocd
      ;;
    "")
      section_kro
      section_ack_controllers
      section_instances
      section_ack_resources
      section_argocd
      ;;
    *) log_error "Unknown section '${FILTER_SECTION}'. Valid: kro | ack | instances | argocd"; exit 1 ;;
  esac

  dump_json

  sep
  log_success "Report complete."
  log_info "Output written to: ${FILE_OUT}"
}

main "$@"
