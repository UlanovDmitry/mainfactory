#!/usr/bin/env bash
# One-time setup: local Docker registry + k3s insecure mirror on localhost:5000.
# Run: sudo ./setup-registry.sh
set -euo pipefail

REGISTRY_PORT="${REGISTRY_PORT:-5000}"
REGISTRY_NAME="${REGISTRY_NAME:-mainfactory-registry}"
REGISTRIES_FILE="/etc/rancher/k3s/registries.yaml"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if ! systemctl is-active --quiet k3s; then
  echo "k3s is not running. Start it first: sudo systemctl start k3s" >&2
  exit 1
fi
if ! command -v docker >/dev/null; then
  echo "docker not found" >&2
  exit 1
fi

if docker ps --format '{{.Names}}' | grep -qx "${REGISTRY_NAME}"; then
  echo "Registry container already running: ${REGISTRY_NAME}"
elif docker ps -a --format '{{.Names}}' | grep -qx "${REGISTRY_NAME}"; then
  docker start "${REGISTRY_NAME}"
  echo "Started existing registry container: ${REGISTRY_NAME}"
else
  docker run -d \
    --restart=always \
    --name "${REGISTRY_NAME}" \
    -p "127.0.0.1:${REGISTRY_PORT}:5000" \
    registry:2
  echo "Created registry container: ${REGISTRY_NAME} on 127.0.0.1:${REGISTRY_PORT}"
fi

mkdir -p /etc/rancher/k3s
cat >"${REGISTRIES_FILE}" <<EOF
mirrors:
  "localhost:${REGISTRY_PORT}":
    endpoint:
      - "http://localhost:${REGISTRY_PORT}"
  "127.0.0.1:${REGISTRY_PORT}":
    endpoint:
      - "http://127.0.0.1:${REGISTRY_PORT}"
configs:
  "localhost:${REGISTRY_PORT}":
    tls:
      insecure_skip_verify: true
  "127.0.0.1:${REGISTRY_PORT}":
    tls:
      insecure_skip_verify: true
EOF
chmod 644 "${REGISTRIES_FILE}"

systemctl restart k3s

for _ in $(seq 1 60); do
  if kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml get nodes &>/dev/null; then
    break
  fi
  sleep 1
done

echo "Done."
echo "  registry: 127.0.0.1:${REGISTRY_PORT}"
echo "  k3s mirrors: ${REGISTRIES_FILE}"
echo
echo "Next (as your user):"
echo "  cd deploy/k3s && ./push-images.sh && ./apply.sh"
