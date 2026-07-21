#!/usr/bin/env bash
# Persist Codex transcripts independently from per-container runtime state.

set -euo pipefail

codex_home="${CODEX_HOME:-/home/vscode/.codex}"
history_home="${CODEX_HISTORY_HOME:-/home/vscode/.codex-history}"
host_sessions="${CODEX_HOST_SESSIONS:-/mnt/codex-host-sessions}"

shared_sessions="${history_home}/sessions"
codex_sessions="${codex_home}/sessions"

mkdir -p "${codex_home}" "${shared_sessions}"

if [[ -L "${codex_sessions}" ]]; then
  linked_target="$(readlink -f "${codex_sessions}")"
  expected_target="$(readlink -f "${shared_sessions}")"
  if [[ "${linked_target}" != "${expected_target}" ]]; then
    echo "ERROR: ${codex_sessions} points to ${linked_target}, not ${expected_target}." >&2
    exit 1
  fi
elif [[ -d "${codex_sessions}" ]]; then
  # Preserve any chats created before split persistence was enabled. Keep the
  # original directory as a backup rather than deleting it.
  cp -a "${codex_sessions}/." "${shared_sessions}/"
  backup="${codex_sessions}.pre-shared-history"
  if [[ -e "${backup}" ]]; then
    backup="${backup}.$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  mv "${codex_sessions}" "${backup}"
  ln -s "${shared_sessions}" "${codex_sessions}"
  echo "Codex history: migrated existing sessions; backup retained at ${backup}."
elif [[ -e "${codex_sessions}" ]]; then
  echo "ERROR: ${codex_sessions} exists but is not a directory or symlink." >&2
  exit 1
else
  ln -s "${shared_sessions}" "${codex_sessions}"
fi

imported=0
if [[ -d "${host_sessions}" ]]; then
  while IFS= read -r -d '' source_file; do
    relative_path="${source_file#"${host_sessions}/"}"
    destination_file="${shared_sessions}/${relative_path}"
    mkdir -p "$(dirname "${destination_file}")"

    if [[ ! -f "${destination_file}" ]] || ! cmp -s "${source_file}" "${destination_file}"; then
      cp --preserve=mode,timestamps "${source_file}" "${destination_file}"
      imported=$((imported + 1))
    fi
  done < <(find "${host_sessions}" -type f -name '*.jsonl' -print0 2>/dev/null)
fi

if (( imported > 0 )); then
  echo "Codex history: imported ${imported} host session file(s)."
else
  echo "Codex history: shared sessions are current."
fi
