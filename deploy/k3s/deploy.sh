#!/usr/bin/env bash
# Build, push to local registry, apply manifests, restart handlers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"${SCRIPT_DIR}/push-images.sh"
"${SCRIPT_DIR}/apply.sh"

kubectl rollout restart deployment/bot-handler deployment/server-handler -n mainfactory
kubectl rollout status deployment/bot-handler -n mainfactory --timeout=120s
kubectl rollout status deployment/server-handler -n mainfactory --timeout=120s

echo "Deployed. NodePorts: bot 30900, server 30901"
