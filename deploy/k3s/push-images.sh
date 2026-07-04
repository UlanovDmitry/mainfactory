#!/usr/bin/env bash
# Build handler images and push to the local registry (localhost:5000).
set -euo pipefail

REGISTRY="${REGISTRY:-localhost:5000}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HANDLERS="${SCRIPT_DIR}/../../handlers"

if ! docker info >/dev/null 2>&1; then
  echo "docker is not available" >&2
  exit 1
fi

if ! curl -sf "http://${REGISTRY}/v2/" >/dev/null; then
  echo "Registry not reachable at http://${REGISTRY}/v2/" >&2
  echo "Run once: sudo ${SCRIPT_DIR}/setup-registry.sh" >&2
  exit 1
fi

echo "Building bot-handler..."
docker build -f "${HANDLERS}/cmd/bot-handler/Dockerfile" -t bot-handler:latest "${HANDLERS}"

echo "Building server-handler..."
docker build -f "${HANDLERS}/cmd/server-handler/Dockerfile" -t server-handler:latest "${HANDLERS}"

docker tag bot-handler:latest "${REGISTRY}/bot-handler:latest"
docker tag server-handler:latest "${REGISTRY}/server-handler:latest"

echo "Pushing to ${REGISTRY}..."
docker push "${REGISTRY}/bot-handler:latest"
docker push "${REGISTRY}/server-handler:latest"

echo "Done: ${REGISTRY}/bot-handler:latest, ${REGISTRY}/server-handler:latest"
