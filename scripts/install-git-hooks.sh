#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
HOOKS_DIR="$REPO_ROOT/.githooks"
GIT_HOOKS_DIR="$REPO_ROOT/.git/hooks"

if [[ ! -d "$GIT_HOOKS_DIR" ]]; then
  echo "This repository doesn't look like a git repo (no .git/hooks). Run from repo root."
  exit 1
fi

echo "Installing git hooks from $HOOKS_DIR to $GIT_HOOKS_DIR"
for hook in "$HOOKS_DIR"/*; do
  hook_name="$(basename "$hook")"
  target="$GIT_HOOKS_DIR/$hook_name"
  if [[ -f "$target" ]]; then
    echo "Backing up existing hook: $target -> ${target}.bak"
    mv "$target" "${target}.bak"
  fi
  ln -sfn "$hook" "$target"
  chmod +x "$hook"
  echo "Installed $hook_name"
done

echo "Git hooks installed. To enable auto-push on commit, run:"
echo "  git config hooks.docker.autoPush true"
echo "Or enable per-user via:"
echo "  git config --global hooks.docker.autoPush true"

exit 0
