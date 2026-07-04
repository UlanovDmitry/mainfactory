#!/usr/bin/env bash
# One-time setup: persistent kubectl access for the current user on k3s.
# Run: sudo ./setup-kubectl-access.sh [username]
set -euo pipefail

TARGET_USER="${1:-${SUDO_USER:-${USER}}}"
if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0 [username]" >&2
  exit 1
fi
if ! id "${TARGET_USER}" &>/dev/null; then
  echo "User not found: ${TARGET_USER}" >&2
  exit 1
fi
if ! systemctl is-active --quiet k3s; then
  echo "k3s is not running. Start it first: sudo systemctl start k3s" >&2
  exit 1
fi

DROPIN_DIR="/etc/systemd/system/k3s.service.d"
DROPIN_FILE="${DROPIN_DIR}/kubeconfig-access.conf"

mkdir -p "${DROPIN_DIR}"
cat >"${DROPIN_FILE}" <<'EOF'
[Service]
# Keep /etc/rancher/k3s/k3s.yaml readable after every k3s restart.
Environment="K3S_KUBECONFIG_MODE=644"
EOF

systemctl daemon-reload
systemctl restart k3s

# Wait until k3s API is up and kubeconfig is rewritten.
for _ in $(seq 1 30); do
  if [[ -r /etc/rancher/k3s/k3s.yaml ]] && kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml get nodes &>/dev/null; then
    break
  fi
  sleep 1
done

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
KUBE_DIR="${TARGET_HOME}/.kube"
KUBE_CONFIG="${KUBE_DIR}/config"

install -d -m 700 -o "${TARGET_USER}" -g "${TARGET_USER}" "${KUBE_DIR}"
install -m 600 -o "${TARGET_USER}" -g "${TARGET_USER}" /etc/rancher/k3s/k3s.yaml "${KUBE_CONFIG}"

PROFILE_FILE="/etc/profile.d/k3s-kubeconfig.sh"
cat >"${PROFILE_FILE}" <<EOF
# k3s kubeconfig for login shells (${TARGET_USER})
if [[ -z "\${KUBECONFIG:-}" && -f "${KUBE_CONFIG}" ]]; then
  export KUBECONFIG="${KUBE_CONFIG}"
fi
EOF
chmod 644 "${PROFILE_FILE}"

echo "Done."
echo "  systemd drop-in: ${DROPIN_FILE}"
echo "  kubeconfig copy: ${KUBE_CONFIG} (owner: ${TARGET_USER})"
echo "  profile hook:    ${PROFILE_FILE}"
echo
echo "Verify as ${TARGET_USER}:"
echo "  kubectl get nodes"
