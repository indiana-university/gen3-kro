#!/usr/bin/env bash
set -euo pipefail

# scripts/docker-build-push.sh
# Build and optionally push docker image tagged with git tag/date/sha

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
cd "$REPO_ROOT"

DOCKER_REPO="${DOCKER_REPO:-jayadeyemi/gen3-kro}"
VERSION_FILE="${REPO_ROOT}/.version"

# Read version from file or default
if [[ -f "$VERSION_FILE" ]]; then
  VERSION="v$(cat "$VERSION_FILE")"
else
  VERSION="v0.0.0"
fi

GIT_SHA="$(git rev-parse --short HEAD)"
DATE="$(date +%Y%m%d)"
TAG="${VERSION}-${DATE}-g${GIT_SHA}"

echo "[docker-build-push] Repository: ${DOCKER_REPO}"
echo "[docker-build-push] Tag: ${TAG}"

echo "[docker-build-push] Building image..."
docker build -t "${DOCKER_REPO}:${TAG}" .

if [[ "${DOCKER_PUSH:-false}" == "true" ]]; then
  if [[ -n "${DOCKER_USERNAME:-}" ]]; then
    echo "[docker-build-push] Logging into Docker registry as ${DOCKER_USERNAME}"
    echo "${DOCKER_PASSWORD:-}" | docker login --username "${DOCKER_USERNAME}" --password-stdin
  else
    echo "[docker-build-push] DOCKER_USERNAME not set; will attempt to push with existing docker credentials"
  fi

  echo "[docker-build-push] Pushing ${DOCKER_REPO}:${TAG}"
  docker push "${DOCKER_REPO}:${TAG}"

  if [[ "${DOCKER_TAG_LATEST:-false}" == "true" ]]; then
    echo "[docker-build-push] Tagging and pushing :latest"
    docker tag "${DOCKER_REPO}:${TAG}" "${DOCKER_REPO}:latest"
    docker push "${DOCKER_REPO}:latest"
  fi
else
  echo "[docker-build-push] DOCKER_PUSH not enabled; image available locally as ${DOCKER_REPO}:${TAG}"
fi

echo "[docker-build-push] Done"
exit 0
